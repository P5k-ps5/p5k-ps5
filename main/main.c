// p5k-ps5, fase 1: el ESP32-S3 se presenta como mando de PS4 por el USB nativo
// y se mueve con órdenes de texto (por el COM, o por el mismo cable USB en modo Mac).
//
// LED:   rojo = sin conectar · verde = conectado al Mac · cian = conectado en modo consola
//        destello azul = el aparato ha pedido algo de configuración
// BOOT:  pulsación corta = botón X · mantener 2 s y soltar = cambiar de modo (consola -> mac -> dualsense)
//        mantener 10 s = rescate de la WiFi (red propia abierta y sin contraseña)

#include <stdbool.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "esp_littlefs.h"
#include "esp_ota_ops.h"
#include "nvs_flash.h"
#include "nvs.h"
#include "led_strip.h"
#include "puente.h"
#include "motor.h"

#define PIN_LED    48
#define PIN_BOTON  0     // botón BOOT: vale 0 mientras lo pulsas
#define BRILLO     20

static const char *TAG = "puente";
static modo_t modo = MODO_MAC;
static led_strip_handle_t led;

modo_t modo_actual(void) { return modo; }
bool modo_mac(void) { return modo == MODO_MAC; }

static const char *nombre_modo(modo_t m)
{
    switch (m) {
    case MODO_MAC:       return "mac";
    case MODO_CONSOLA:   return "consola";
    case MODO_DUALSENSE: return "dualsense";
    default:             return "?";
    }
}

const char *modo_nombre(void) { return nombre_modo(modo); }

static void color(uint8_t r, uint8_t g, uint8_t b)
{
    led_strip_set_pixel(led, 0, r, g, b);
    led_strip_refresh(led);
}

void modo_poner(modo_t m)
{
    nvs_handle_t nvs;
    if (nvs_open("puente", NVS_READWRITE, &nvs) == ESP_OK) {
        nvs_set_u8(nvs, "modo", (uint8_t)m);
        nvs_commit(nvs);
        nvs_close(nvs);
    }
    responder("Modo %s guardado. Reiniciando...", nombre_modo(m));
    color(BRILLO, 0, BRILLO);
    vTaskDelay(pdMS_TO_TICKS(300));
    esp_restart();
}

static void leer_modo(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        nvs_flash_init();
    }
    nvs_handle_t nvs;
    uint8_t valor = (uint8_t)MODO_MAC;
    if (nvs_open("puente", NVS_READONLY, &nvs) == ESP_OK) {
        // Clave nueva "modo" (0/1/2); si no está, se migra de la antigua "modo_mac" (0/1)
        if (nvs_get_u8(nvs, "modo", &valor) != ESP_OK) {
            uint8_t viejo = 1;
            nvs_get_u8(nvs, "modo_mac", &viejo);
            valor = viejo ? (uint8_t)MODO_MAC : (uint8_t)MODO_CONSOLA;
        }
        nvs_close(nvs);
    }
    modo = (valor <= MODO_DUALSENSE) ? (modo_t)valor : MODO_MAC;
}

// La partición «datos» (LittleFS) en /datos: perfiles.json y medidor.json del motor
static void montar_datos(void)
{
    esp_vfs_littlefs_conf_t c = {
        .base_path = "/datos",
        .partition_label = "datos",
        .format_if_mount_failed = true,
    };
    esp_err_t e = esp_vfs_littlefs_register(&c);
    if (e != ESP_OK) ESP_LOGE(TAG, "No se pudo montar /datos (%s): los perfiles no se guardarán", esp_err_to_name(e));
}

// Lo que el motor no hace en su vuelta de 1 ms: guardar los cambios (medio segundo después) y analizar ráfagas
static void tarea_lenta(void *arg)
{
    while (true) {
        vTaskDelay(pdMS_TO_TICKS(500));
        motor_lento();
    }
}

// Tras una actualización por WiFi, el firmware nuevo se da por bueno si lleva 30 s en marcha con la WiFi y
// el servidor web arrancados. Si se cuelga o se reinicia antes, la placa vuelve sola al anterior.
static void tarea_validar(void *arg)
{
    vTaskDelay(pdMS_TO_TICKS(30000));
    esp_ota_img_states_t estado;
    const esp_partition_t *actual = esp_ota_get_running_partition();
    if (esp_ota_get_state_partition(actual, &estado) == ESP_OK && estado == ESP_OTA_IMG_PENDING_VERIFY) {
        esp_ota_mark_app_valid_cancel_rollback();
        ESP_LOGI(TAG, "Firmware nuevo confirmado (%s)", actual->label);
    }
    vTaskDelete(NULL);
}

static void crear_led(void)
{
    led_strip_config_t tira = {
        .strip_gpio_num = PIN_LED,
        .max_leds = 1,
        .led_model = LED_MODEL_WS2812,
        .color_component_format = LED_STRIP_COLOR_COMPONENT_FMT_GRB,
    };
    led_strip_rmt_config_t rmt = {
        .clk_src = RMT_CLK_SRC_DEFAULT,
        .resolution_hz = 10 * 1000 * 1000,
    };
    ESP_ERROR_CHECK(led_strip_new_rmt_device(&tira, &rmt, &led));
}

void app_main(void)
{
    crear_led();
    gpio_config_t boton = {
        .pin_bit_mask = 1ULL << PIN_BOTON,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    ESP_ERROR_CHECK(gpio_config(&boton));

    leer_modo();
    ESP_LOGI(TAG, "Arrancando en modo %s", nombre_modo(modo));
    montar_datos();
    motor_iniciar("/datos");                 // el motor (Rust): perfiles, anti-recoil, ayuda, macros...
    xTaskCreatePinnedToCore(tarea_lenta, "lento", 16384, NULL, 2, NULL, 0);
    ordenes_iniciar();
    usb_ps4_iniciar(modo);

    // El lado host (MAX3421E) lee el DualSense real: en modo dualsense (relé con la PS5) y en modo consola
    // (mando de PS4 para el P5Mate, con el perfil aplicado en la placa). Si el MAX3421E no está, la tarea
    // se da cuenta (lee el registro REVISION) y se desactiva sola, sin afectar al resto.
    if (modo != MODO_MAC) host_mando_iniciar();

    // WiFi (red de casa o red propia con portal) y la app web
    red_iniciar();
    web_iniciar();
    xTaskCreate(tarea_validar, "validar", 3072, NULL, 2, NULL);

    uint32_t peticiones_antes = 0;
    int destello = 0;      // pasos de 20 ms que le quedan al destello azul
    int pulsado_pasos = 0; // cuánto lleva BOOT pulsado
    while (true) {
        bool pulsado = gpio_get_level(PIN_BOTON) == 0;
        if (pulsado) {
            if (++pulsado_pasos == 500) red_rescate();               // 10 s: rescate de la WiFi
            // Mientras se mantiene: morado desde los 2 s («suelta para cambiar de modo»), blanco a los 10 s
            if (pulsado_pasos >= 500) { color(BRILLO, BRILLO, BRILLO); vTaskDelay(pdMS_TO_TICKS(20)); continue; }
            if (pulsado_pasos >= 100) { color(BRILLO, 0, BRILLO / 2); vTaskDelay(pdMS_TO_TICKS(20)); continue; }
        } else {
            if (pulsado_pasos > 1 && pulsado_pasos < 100) {
                mando_pulsar(BTN_CRUZ, 150);
                ESP_LOGI(TAG, "BOOT -> X");
            } else if (pulsado_pasos >= 100 && pulsado_pasos < 500) {
                modo_poner((modo + 1) % 3);                          // consola -> mac -> dualsense
            }
            pulsado_pasos = 0;
        }

        uint32_t peticiones = usb_peticiones();
        if (peticiones != peticiones_antes) {
            peticiones_antes = peticiones;
            destello = 5;
        }
        if (destello > 0) { destello--; color(0, 0, BRILLO); }
        else if (!usb_conectado()) color(BRILLO, 0, 0);               // rojo: sin conectar
        else if (modo == MODO_MAC) color(0, BRILLO, 0);               // verde: mac
        else if (modo == MODO_CONSOLA) color(0, BRILLO, BRILLO);      // cian: consola (DS4)
        else color(BRILLO, 0, BRILLO);                                // magenta: dualsense

        vTaskDelay(pdMS_TO_TICKS(20));
    }
}
