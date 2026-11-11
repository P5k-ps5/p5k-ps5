// Órdenes de texto para mover el mando a mano. Llegan por el COM (UART) o por el
// puerto serie USB en modo Mac. Escribe "ayuda" para ver la lista.

#include <ctype.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "driver/uart.h"
#include "esp_system.h"
#include "soc/rtc_cntl_reg.h"
#include "puente.h"
#include "motor.h"

#define LARGO_LINEA 320           // cabe un trozo de ajustes en base64 («ajustes trozo …»)
#define FUENTES     2    // 0 = COM, 1 = serie USB

// Además del texto, el programa del Mac manda el mando entero en tramas binarias:
//   A5 5A | botones (2, bajo primero) cruceta lx ly rx ry l2 r2 | xor de esos 9 bytes
// Los bytes A5 no son imprimibles, así que no se confunden con una orden de texto.
#define TRAMA_INICIO1 0xA5
#define TRAMA_INICIO2 0x5A
#define TRAMA_DATOS   9

static QueueHandle_t cola;
static char linea[FUENTES][LARGO_LINEA];
static size_t largo[FUENTES];
static int trama_pos[FUENTES];           // 0 = texto; 1 = tras A5; 2.. = leyendo la trama
static uint8_t trama[FUENTES][TRAMA_DATOS + 1];
static uint32_t tramas_buenas, tramas_malas;

static void aplicar_trama(const uint8_t *t)
{
    uint8_t xor = 0;
    for (int i = 0; i < TRAMA_DATOS; i++) xor ^= t[i];
    if (xor != t[TRAMA_DATOS]) { tramas_malas++; return; }
    mando_t m = {
        .botones = (uint16_t)(t[0] | (t[1] << 8)),
        .dpad = t[2] <= DPAD_CENTRO ? t[2] : DPAD_CENTRO,
        .lx = t[3], .ly = t[4], .rx = t[5], .ry = t[6],
        .l2 = t[7], .r2 = t[8],
    };
    mando_poner(&m);
    tramas_buenas++;
}

typedef struct { const char *nombre; int boton; int dpad; } nombre_boton_t;

static const nombre_boton_t nombres[] = {
    { "x", BTN_CRUZ, -1 },         { "cruz", BTN_CRUZ, -1 },
    { "circulo", BTN_CIRCULO, -1 }, { "cuadrado", BTN_CUADRADO, -1 },
    { "triangulo", BTN_TRIANGULO, -1 },
    { "l1", BTN_L1, -1 }, { "r1", BTN_R1, -1 }, { "l2", BTN_L2, -1 }, { "r2", BTN_R2, -1 },
    { "l3", BTN_L3, -1 }, { "r3", BTN_R3, -1 },
    { "share", BTN_SHARE, -1 },     { "options", BTN_OPTIONS, -1 },
    { "ps", BTN_PS, -1 },           { "tactil", BTN_TACTIL, -1 },
    { "arriba", -1, DPAD_ARRIBA },  { "abajo", -1, DPAD_ABAJO },
    { "izquierda", -1, DPAD_IZQUIERDA }, { "derecha", -1, DPAD_DERECHA },
};

static const nombre_boton_t *buscar(const char *nombre)
{
    for (size_t i = 0; i < sizeof(nombres) / sizeof(nombres[0]); i++) {
        if (strcasecmp(nombre, nombres[i].nombre) == 0) return &nombres[i];
    }
    return NULL;
}

void responder(const char *formato, ...)
{
    char texto[400];
    va_list args;
    va_start(args, formato);
    int n = vsnprintf(texto, sizeof(texto) - 2, formato, args);
    va_end(args);
    if (n < 0) return;
    if (n > (int)sizeof(texto) - 3) n = sizeof(texto) - 3;
    printf("%s\n", texto);
    texto[n++] = '\r';
    texto[n++] = '\n';
    usb_serie_escribir(texto, n);
}

static void ayuda(void)
{
    responder("Órdenes:");
    responder("  pulsa <botón> [ms]      pulsa y suelta (150 ms si no dices nada)");
    responder("  manten <botón>          deja pulsado hasta 'suelta'");
    responder("  suelta [botón]          suelta uno o todo (sticks al centro)");
    responder("  stick <izq|der> <x> <y> de -100 a 100; y positiva = arriba");
    responder("  gatillo <l2|r2> <0-100>");
    responder("  demo                    el stick izquierdo da vueltas 4 s");
    responder("  estado                  qué ha pedido el aparato por USB");
    responder("  modo <mac|consola|dualsense>  mac = con serie; consola = P5Mate; dualsense = mando de PS5");
    responder("  grabar                  reinicia en modo grabación (para flashear)");
    responder("  reinicia");
    responder("Botones: x circulo cuadrado triangulo l1 r1 l2 r2 l3 r3 share options ps tactil");
    responder("         arriba abajo izquierda derecha");
}

static void tarea_demo(void *arg)
{
    for (int i = 0; i <= 400; i++) {   // 4 s a 100 pasos por segundo: una vuelta por segundo
        float a = i * 2.0f * (float)M_PI / 100.0f;
        mando_stick(false, (int)(100 * cosf(a)), (int)(100 * sinf(a)));
        vTaskDelay(pdMS_TO_TICKS(10));
    }
    mando_stick(false, 0, 0);
    responder("Demo terminada");
    vTaskDelete(NULL);
}

static void ejecutar(char *texto)
{
    char *palabras[5] = {0};
    int n = 0;
    for (char *p = strtok(texto, " \t"); p && n < 5; p = strtok(NULL, " \t")) palabras[n++] = p;
    if (n == 0) return;
    if (sincro_orden(palabras, n)) return;          // ajustes con las apps (sincro.c)
    const char *orden = palabras[0];

    if (!strcasecmp(orden, "ayuda") || !strcmp(orden, "?")) {
        ayuda();
    } else if (!strcasecmp(orden, "pulsa") || !strcasecmp(orden, "manten")) {
        const nombre_boton_t *b = n > 1 ? buscar(palabras[1]) : NULL;
        if (!b) { responder("¿Qué botón? Escribe 'ayuda'"); return; }
        int ms = !strcasecmp(orden, "manten") ? 0 : (n > 2 ? atoi(palabras[2]) : 150);
        if (b->boton >= 0) mando_pulsar(b->boton, ms);
        else mando_dpad(b->dpad, ms);
        responder("ok: %s %s%s", orden, b->nombre, ms ? "" : " (hasta 'suelta')");
    } else if (!strcasecmp(orden, "suelta")) {
        if (n == 1) { mando_soltar_todo(); responder("ok: todo suelto"); return; }
        const nombre_boton_t *b = buscar(palabras[1]);
        if (!b) { responder("¿Qué botón? Escribe 'ayuda'"); return; }
        if (b->boton >= 0) mando_soltar(b->boton); else mando_dpad(DPAD_CENTRO, 0);
        responder("ok: suelto %s", b->nombre);
    } else if (!strcasecmp(orden, "stick") && n == 4) {
        bool derecho = !strncasecmp(palabras[1], "der", 3);
        mando_stick(derecho, atoi(palabras[2]), atoi(palabras[3]));
        responder("ok: stick %s", derecho ? "derecho" : "izquierdo");
    } else if (!strcasecmp(orden, "gatillo") && n == 3) {
        bool derecho = !strcasecmp(palabras[1], "r2");
        mando_gatillo(derecho, atoi(palabras[2]));
        responder("ok: gatillo %s", derecho ? "R2" : "L2");
    } else if (!strcasecmp(orden, "demo")) {
        xTaskCreate(tarea_demo, "demo", 3072, NULL, 5, NULL);
        responder("Demo: el stick izquierdo da vueltas 4 s");
    } else if (!strcasecmp(orden, "estado")) {
        const char *desc = modo_actual() == MODO_MAC ? "mac (mando PS4 + puerto serie)"
                         : modo_actual() == MODO_CONSOLA ? "consola (mando PS4, para el P5Mate)"
                         : "dualsense (se presenta como mando de PS5)";
        responder("Modo: %s", desc);
        responder("Tramas del Mac: %lu buenas, %lu malas",
                  (unsigned long)tramas_buenas, (unsigned long)tramas_malas);
        usb_estado();
        responder("Mando real (MAX3421E): %s", host_mando_listo() ? "conectado" : "no");
        red_estado();
        char *clave = motor_clave();
        responder("Clave de la app web: %s", clave ? clave : "?");
        motor_liberar(clave);
    } else if (!strcasecmp(orden, "wifi") && n == 2 && !strcasecmp(palabras[1], "olvidar")) {
        // Por si no se puede entrar por ningún lado: olvida la red de casa y abre la red propia
        red_olvidar();
        responder("Red de casa olvidada: la placa abre su red propia");
    } else if (!strcasecmp(orden, "wifi") && n == 2 && !strcasecmp(palabras[1], "rescate")) {
        red_rescate();
        responder("Rescate: red propia abierta y sin contraseña");
    } else if (!strcasecmp(orden, "wifi") && n == 2 && !strcasecmp(palabras[1], "buscar")) {
        red_buscar();
        responder("Buscando redes... (mira «wifi» en unos segundos)");
    } else if (!strcasecmp(orden, "wifi") && n == 1) {
        red_estado();
        red_listar();
    } else if (!strcasecmp(orden, "directo") && n == 2) {
        int modo = !strcasecmp(palabras[1], "si") ? 1 : atoi(palabras[1]);
        usb_directo(modo);
        responder("Relé en modo %d (0 normal, 1 directo, 2 stick derecho 0x80, 3 byte de relleno cambiado, 4 stick derecho X -1)", modo);
    } else if (!strcasecmp(orden, "captura") && n == 2) {
        usb_capturar(atoi(palabras[1]));
    } else if (!strcasecmp(orden, "volcar")) {
        usb_volcar_captura();
    } else if (!strcasecmp(orden, "informes")) {
        usb_volcar_informes();
    } else if (!strcasecmp(orden, "medir")) {
        // Cuánto tarda el motor en esta placa (perfil activo, anti-recoil y ayuda encendidos, disparando)
        float peor = 0;
        float medio = motor_medir(2000, &peor);
        responder("Motor: %.1f us por vuelta de media, %.1f us la peor (cada vuelta tiene 1000 us)", medio, peor);
    } else if (!strcasecmp(orden, "modo") && n == 2) {
        if (!strcasecmp(palabras[1], "mac")) modo_poner(MODO_MAC);
        else if (!strcasecmp(palabras[1], "consola")) modo_poner(MODO_CONSOLA);
        else if (!strcasecmp(palabras[1], "dualsense") || !strcasecmp(palabras[1], "ds5")) modo_poner(MODO_DUALSENSE);
        else responder("Modos: mac, consola o dualsense");
    } else if (!strcasecmp(orden, "grabar")) {
        // Reinicia en modo grabación, como BOOT + RST pero sin tocar la placa
        responder("Reiniciando en modo grabación...");
        vTaskDelay(pdMS_TO_TICKS(100));
        REG_WRITE(RTC_CNTL_OPTION1_REG, RTC_CNTL_FORCE_DOWNLOAD_BOOT);
        esp_restart();
    } else if (!strcasecmp(orden, "reinicia")) {
        responder("Reiniciando...");
        vTaskDelay(pdMS_TO_TICKS(100));
        esp_restart();
    } else {
        responder("No entiendo '%s'. Escribe 'ayuda'", orden);
    }
}

void ordenes_bytes(const uint8_t *datos, size_t n, int fuente)
{
    if (fuente < 0 || fuente >= FUENTES) return;
    for (size_t i = 0; i < n; i++) {
        uint8_t b = datos[i];
        int *pos = &trama_pos[fuente];
        if (*pos == 0 && b == TRAMA_INICIO1) { *pos = 1; continue; }
        if (*pos == 1) {
            if (b == TRAMA_INICIO2) { *pos = 2; continue; }
            *pos = 0;   // no era una trama: sigue como texto
        }
        if (*pos >= 2) {
            trama[fuente][*pos - 2] = b;
            if (++*pos == 2 + TRAMA_DATOS + 1) {
                aplicar_trama(trama[fuente]);
                *pos = 0;
            }
            continue;
        }

        char c = (char)b;
        if (c == '\r' || c == '\n') {
            if (largo[fuente] == 0) continue;
            linea[fuente][largo[fuente]] = '\0';
            xQueueSend(cola, linea[fuente], 0);
            largo[fuente] = 0;
        } else if (largo[fuente] < LARGO_LINEA - 1 && isprint((unsigned char)c)) {
            linea[fuente][largo[fuente]++] = c;
        }
    }
}

static void tarea_ordenes(void *arg)
{
    char texto[LARGO_LINEA];
    while (true) {
        if (xQueueReceive(cola, texto, portMAX_DELAY)) ejecutar(texto);
    }
}

static void tarea_com(void *arg)
{
    const uart_port_t com = CONFIG_ESP_CONSOLE_UART_NUM;
    uint8_t datos[128];
    while (true) {
        // uart_read_bytes no vuelve hasta llenar lo que se le pide (o hasta el tiempo límite):
        // pidiendo 64 bytes, las tramas del Mac (12 bytes) llegaban a golpes cada 20 ms.
        // Se espera solo al primer byte y luego se recoge, sin esperar, lo que ya haya llegado.
        int n = uart_read_bytes(com, datos, 1, portMAX_DELAY);
        if (n <= 0) continue;
        size_t hay = 0;
        uart_get_buffered_data_len(com, &hay);
        if (hay > sizeof(datos) - 1) hay = sizeof(datos) - 1;
        if (hay > 0) {
            int mas = uart_read_bytes(com, datos + 1, hay, 0);
            if (mas > 0) n += mas;
        }
        ordenes_bytes(datos, n, 0);
    }
}

void ordenes_iniciar(void)
{
    cola = xQueueCreate(16, LARGO_LINEA);
    ESP_ERROR_CHECK(uart_driver_install(CONFIG_ESP_CONSOLE_UART_NUM, 512, 0, 0, NULL, 0));
    xTaskCreate(tarea_ordenes, "ordenes", 16384, NULL, 5, NULL);   // el motor (Rust) lee y escribe JSON
    xTaskCreate(tarea_com, "com", 3072, NULL, 5, NULL);
}
