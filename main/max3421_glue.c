// Glue entre TinyUSB (host) y el MAX3421E, por SPI, en el ESP32-S3.
// TinyUSB trae el driver del MAX3421E (hcd_max3421.c); aquí van las 3 funciones de board que pide
// (chip select, transferencia SPI, enable de interrupción) más la inicialización del bus.
//
// En vez de una ISR en el pin INT (el SPI del ESP-IDF no es seguro desde interrupción), se SONDEA el
// pin en la tarea de host: max3421_int_pendiente() dice si hay que llamar a tuh_int_handler().
#include <stdbool.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/spi_master.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "tusb.h"
#include "puente.h"

#define PIN_SCK  12
#define PIN_MOSI 11
#define PIN_MISO 13
#define PIN_CS   10
#define PIN_INT   9
#define PIN_RES   8   // pin RES del MAX3421E (MAX_RST): a nivel bajo el chip está en reset y su oscilador parado

static const char *TAG = "max3421";
static spi_device_handle_t spi;
static volatile bool int_habilitada;

// Velocidad del SPI. El MAX3421E admite 26 MHz, pero con cables Dupont sueltos no es fiable;
// 4 MHz sobra para un mando (un paquete de 64 bytes tarda ~130 us).
#define SPI_HZ (4 * 1000 * 1000)

static void bus_iniciar(int sck, int mosi, int hz)
{
    spi_bus_config_t bus = {
        .sclk_io_num = sck,
        .mosi_io_num = mosi,
        .miso_io_num = PIN_MISO,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = 64,
    };
    // Sin DMA: las transferencias son de 64 bytes como mucho (el FIFO del MAX), que el SPI del S3 hace
    // con sus propios registros. Con DMA, cada recepción a un búfer sin alinear pedía memoria DMA nueva
    // y, con la WiFi y la web gastando RAM interna, fallaba («Failed to allocate priv RX buffer»): se
    // perdían informes del mando y la PS5 dejaba de recibirlos.
    ESP_ERROR_CHECK(spi_bus_initialize(SPI2_HOST, &bus, SPI_DMA_DISABLED));

    spi_device_interface_config_t dev = {
        .clock_speed_hz = hz,
        .mode = 0,                            // SPI modo 0
        .spics_io_num = -1,                   // el CS lo manejamos a mano (lo pide TinyUSB)
        .queue_size = 1,
    };
    ESP_ERROR_CHECK(spi_bus_add_device(SPI2_HOST, &dev, &spi));
    gpio_pullup_en(PIN_MISO);   // sin chip que conteste, MISO lee 1 (0xFF) en vez de flotar
}

static void bus_liberar(void)
{
    spi_bus_remove_device(spi);
    spi_bus_free(SPI2_HOST);
}

void max3421_glue_init(void)
{
    bus_iniciar(PIN_SCK, PIN_MOSI, SPI_HZ);

    gpio_config_t cs = { .pin_bit_mask = 1ULL << PIN_CS, .mode = GPIO_MODE_OUTPUT };
    gpio_config(&cs);
    gpio_set_level(PIN_CS, 1);

    // RES: en la placa del MAX va suelto (en el shield original lo sube el Arduino), y si queda bajo el
    // chip contesta por SPI pero no arranca. Lo manejamos desde aquí: un pulso de reset y luego arriba.
    gpio_config_t res = { .pin_bit_mask = 1ULL << PIN_RES, .mode = GPIO_MODE_OUTPUT };
    gpio_config(&res);
    gpio_set_level(PIN_RES, 0);
    vTaskDelay(pdMS_TO_TICKS(5));
    gpio_set_level(PIN_RES, 1);
    vTaskDelay(pdMS_TO_TICKS(5));

    gpio_config_t in = {
        .pin_bit_mask = 1ULL << PIN_INT,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    gpio_config(&in);
    ESP_LOGI(TAG, "SPI y pines del MAX3421E listos (SCK %d MOSI %d MISO %d CS %d INT %d RES %d)",
             PIN_SCK, PIN_MOSI, PIN_MISO, PIN_CS, PIN_INT, PIN_RES);
}

// ¿hay interrupción pendiente del MAX3421E? (INT activo a nivel bajo). La tarea de host lo sondea.
bool max3421_int_pendiente(void)
{
    return int_habilitada && gpio_get_level(PIN_INT) == 0;
}

// Una transferencia de 2 bytes (orden + dato) con su chip select. Devuelve el 2º byte recibido.
static uint8_t registro(uint8_t orden, uint8_t dato)
{
    uint8_t tx[2] = { orden, dato };
    uint8_t rx[2] = { 0, 0 };
    gpio_set_level(PIN_CS, 0);
    spi_transaction_t t = { .length = 16, .tx_buffer = tx, .rxlength = 16, .rx_buffer = rx };
    spi_device_polling_transmit(spi, &t);
    gpio_set_level(PIN_CS, 1);
    return rx[1];
}

// ¿está el MAX3421E conectado? Lee el registro REVISION (18) por SPI. Un chip real devuelve una
// revisión concreta (0x12/0x13/0x16...); sin chip sale 0x00 o 0xFF. Permite arrancar el host solo
// si la placa está, y no colgar el firmware cuando no está.
// Ojo: el chip arranca en SPI half-duplex (no saca nada por MISO), así que antes de leer hay que
// pasarlo a full-duplex escribiendo PINCTL (17) con FDUPSPI, igual que hace TinyUSB en hcd_init.
static uint8_t leer_revision(void)
{
    registro((17u << 3) | 0x02, 0x10 | 0x08);   // PINCTL: FDUPSPI + INTLEVEL
    return registro(18u << 3, 0);               // REVISION, lectura
}

static bool revision_valida(uint8_t rev) { return rev != 0x00 && rev != 0xFF; }

// ¿Arranca el oscilador de 12 MHz? Es lo que hace TinyUSB en hcd_init (reiniciar el chip y esperar
// OSCOKIRQ), pero con límite de tiempo: si no llega, TinyUSB se queda esperando para siempre y cuelga
// el núcleo 1. Además sirve para saber si el SPI va fino a esta velocidad (no basta con un REVISION).
static bool oscilador_ok(void)
{
    registro((15u << 3) | 0x02, 0x20);          // USBCTL: CHIPRES
    registro((15u << 3) | 0x02, 0x00);
    registro((17u << 3) | 0x02, 0x10 | 0x08);   // PINCTL otra vez, por si el reinicio lo ha borrado
    uint8_t irq = 0;
    for (int i = 0; i < 50; i++) {
        irq = registro(13u << 3, 0);            // USBIRQ
        if (irq & 0x01) return true;            // OSCOKIRQ
        vTaskDelay(pdMS_TO_TICKS(1));
    }
    // Diagnóstico: con el pin RES del chip a nivel bajo, el SPI y REVISION responden pero el resto de
    // registros no guarda nada y el oscilador está parado. Se prueba escribiendo USBIEN y leyéndolo.
    registro((14u << 3) | 0x02, 0x01);
    uint8_t usbien = registro(14u << 3, 0);
    registro((14u << 3) | 0x02, 0x00);
    ESP_LOGW(TAG, "    el oscilador no da señal (USBIRQ=0x%02X); USBIEN escrito 0x01, leído 0x%02X%s", irq, usbien,
             usbien == 0x01 ? "" : " -> el chip no guarda registros: ¿está el cable de MAX_RST al GPIO8?");
    return false;
}

// Una combinación de pines y velocidad vale si REVISION sale bien tres veces seguidas y arranca el oscilador
static bool probar(int sck, int mosi, int hz)
{
    bus_liberar();
    bus_iniciar(sck, mosi, hz);
    uint8_t rev = 0;
    bool ok = true;
    for (int i = 0; i < 3 && ok; i++) ok = revision_valida(rev = leer_revision());
    ESP_LOGI(TAG, "  SCK %d, MOSI %d, %d Hz -> REVISION = 0x%02X", sck, mosi, hz, rev);
    return ok && oscilador_ok();
}

bool max3421_presente(void)
{
    // Nivel de MISO en reposo (CS alto): el chip lo deja suelto y la pull-up lo sube a 1.
    // Si se lee 0 aquí, algo tira de MISO a masa (cable cruzado o chip dañado).
    gpio_set_level(PIN_CS, 1);
    ESP_LOGI(TAG, "MISO en reposo = %d (esperado 1)", gpio_get_level(PIN_MISO));

    // Los dos órdenes de SCK/MOSI (la serigrafía de algunas placas los tiene cambiados) y, si a la
    // velocidad normal no va fino, más despacio. Se queda con la primera que funciona.
    static const int velocidades[] = { SPI_HZ, 1000 * 1000, 500 * 1000 };
    static const struct { int sck, mosi; } pines[] = { { PIN_SCK, PIN_MOSI }, { PIN_MOSI, PIN_SCK } };
    for (int v = 0; v < 3; v++) {
        for (int p = 0; p < 2; p++) {
            if (probar(pines[p].sck, pines[p].mosi, velocidades[v])) {
                ESP_LOGI(TAG, "MAX3421E listo: SCK %d, MOSI %d, %d Hz", pines[p].sck, pines[p].mosi, velocidades[v]);
                return true;
            }
        }
    }
    bus_liberar();
    bus_iniciar(PIN_SCK, PIN_MOSI, SPI_HZ);
    return false;
}

// ¿Sigue el chip despierto y en modo host? Al enchufar el mando con la placa encendida, el pico de
// consumo le puede bajar la tensión un instante: si se reinicia del todo vuelve a SPI half-duplex (se
// lee 0xFF), y si no del todo, pierde algún registro (visto: MODE sin el bit HOST, y deja de enumerar).
bool max3421_vivo(void)
{
    if (!revision_valida(registro(18u << 3, 0))) return false;
    return (registro(27u << 3, 0) & 0x01) != 0;   // MODE.HOST
}

// ¿Hay algo enchufado en el USB-A? HRSL: J (bit 7) o K (bit 6) a 1 = el bus no está en SE0.
bool max3421_algo_enchufado(void)
{
    return (registro(31u << 3, 0) & 0xC0) != 0;
}

// Diagnóstico: registros del lado host. HRSL bits 7/6 = JSTATUS/KSTATUS (estado de D+/D-: con un
// mando full-speed conectado, J=1); HIRQ bit 5 = CONDETIRQ (conexión detectada).
void max3421_volcar_estado(uint32_t interrupciones)
{
    uint8_t hirq = registro(25u << 3, 0);
    uint8_t mode = registro(27u << 3, 0);
    uint8_t hrsl = registro(31u << 3, 0);
    ESP_LOGI(TAG, "estado: HIRQ=0x%02X MODE=0x%02X HRSL=0x%02X (J=%d K=%d) INT=%d ints=%lu",
             hirq, mode, hrsl, (hrsl >> 7) & 1, (hrsl >> 6) & 1, gpio_get_level(PIN_INT),
             (unsigned long)interrupciones);
}

// --- Las 3 funciones que pide el HCD del MAX3421E (firmas de hcd_max3421.h) ---

void tuh_max3421_spi_cs_api(uint8_t rhport, bool active)
{
    (void)rhport;
    gpio_set_level(PIN_CS, active ? 0 : 1);
}

bool tuh_max3421_spi_xfer_api(uint8_t rhport, uint8_t const *tx_buf, uint8_t *rx_buf, size_t xfer_bytes)
{
    (void)rhport;
    if (xfer_bytes == 0) return true;
    spi_transaction_t t = {
        .length = xfer_bytes * 8,
        .tx_buffer = tx_buf,
        .rxlength = rx_buf ? xfer_bytes * 8 : 0,
        .rx_buffer = rx_buf,
    };
    return spi_device_polling_transmit(spi, &t) == ESP_OK;
}

void tuh_max3421_int_api(uint8_t rhport, bool enabled)
{
    (void)rhport;
    int_habilitada = enabled;
}
