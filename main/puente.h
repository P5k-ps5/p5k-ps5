// Piezas compartidas del puente de mando.
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

// Botones en el mismo orden que los bits del informe del mando de PS4
enum {
    BTN_CUADRADO, BTN_CRUZ, BTN_CIRCULO, BTN_TRIANGULO,
    BTN_L1, BTN_R1, BTN_L2, BTN_R2,
    BTN_SHARE, BTN_OPTIONS, BTN_L3, BTN_R3,
    BTN_PS, BTN_TACTIL,
    NUM_BOTONES
};

// Cruceta: 0 = arriba y sigue en el sentido de las agujas del reloj; 8 = suelta
enum { DPAD_ARRIBA = 0, DPAD_DERECHA = 2, DPAD_ABAJO = 4, DPAD_IZQUIERDA = 6, DPAD_CENTRO = 8 };

typedef struct {
    uint16_t botones;          // un bit por BTN_*
    uint8_t dpad;              // DPAD_*
    uint8_t lx, ly, rx, ry;    // sticks: 0..255, 128 = centro, Y pequeña = arriba
    uint8_t l2, r2;            // gatillos analógicos: 0..255
} mando_t;

// mando.c: estado del mando que vamos a enviar
void mando_pulsar(int boton, int ms);      // ms <= 0: hasta que se suelte
void mando_soltar(int boton);
void mando_dpad(int dir, int ms);
void mando_stick(bool derecho, int x, int y);   // -100..100, Y positiva = arriba
void mando_gatillo(bool derecho, int valor);    // 0..100
void mando_soltar_todo(void);
void mando_poner(const mando_t *m);        // estado completo que llega del Mac (DualSense)
void mando_copiar(mando_t *salida);        // copia el estado y suelta lo que haya caducado

// main.c: modo guardado en la memoria
typedef enum {
    MODO_CONSOLA = 0,    // solo mando de PS4 (DualShock 4), para el P5Mate
    MODO_MAC = 1,        // mando de PS4 + puerto serie por el mismo cable (para probar con el Mac)
    MODO_DUALSENSE = 2,  // se presenta como DualSense (PS5); paso previo al passthrough de autenticación
} modo_t;

// usb_ps4.c: el ESP32 visto como mando por el USB nativo (PS4 o DualSense según el modo)
void usb_ps4_iniciar(modo_t modo);
bool usb_conectado(void);
uint32_t usb_peticiones(void);             // cuántas peticiones de configuración ha hecho el aparato
void usb_serie_escribir(const char *texto, size_t largo);
void usb_directo(int modo);                 // modo dualsense: pasar el informe real sin tocar (diagnóstico)
void usb_volcar_informes(void);
void usb_capturar(int n);                  // guarda los próximos n informes enviados a la PS5 (y los del mando)
void usb_volcar_captura(void);            // último informe del mando y último enviado a la PS5, en hex
void usb_estado(void);                     // vuelca por las respuestas lo que ha pedido el aparato

// ordenes.c: órdenes de texto que llegan por el COM o por el puerto serie USB
void ordenes_iniciar(void);
void ordenes_bytes(const uint8_t *datos, size_t largo, int fuente);
void responder(const char *formato, ...) __attribute__((format(printf, 1, 2)));

modo_t modo_actual(void);
const char *modo_nombre(void);
void modo_poner(modo_t m);                 // guarda y reinicia
bool modo_mac(void);                       // compat: modo_actual() == MODO_MAC

// host_mando.c: lado host (lee el DualSense real por el MAX3421E) y relé con la PS5. Hito 2.
void host_mando_iniciar(void);
void host_mando_estado(mando_t *salida);   // último estado leído del mando real
void host_mando_contadores(uint32_t c[5]);   // informes, salidas pedidas, juntadas, enviadas, perdidas (y a cero)
bool host_mando_listo(void);               // hay un DualSense real conectado al host
// Relé (se llaman desde el lado device). Los informes van con el report ID en el byte 0.
int host_mando_get(uint8_t tipo, uint8_t id, uint8_t *resp, uint16_t largo);
int host_mando_set(uint8_t tipo, uint8_t id, const uint8_t *datos_sin_id, uint16_t largo);
void host_mando_salida(const uint8_t *rep, uint16_t largo);
bool host_mando_informe(uint8_t *inf, uint16_t *largo);
bool dualsense_parsear(const uint8_t *rep, uint16_t len, mando_t *m);

// red.c: la WiFi (red de casa y red propia con portal cautivo). Ver PLACA-WEB.md.
struct cJSON;
void red_iniciar(void);
bool red_por_ap(uint32_t ip);                    // ¿esa IP está en la red propia de la placa?
bool red_ip_propia(const char *host);            // ¿ese «Host» es la placa? (si no: portal cautivo)
void red_aceptar_portal(uint32_t ip);
bool red_portal_aceptado(uint32_t ip);
void red_conectar(const char *ssid, const char *clave);
void red_olvidar(void);
void red_rescate(void);                          // red propia sin contraseña y abierta (BOOT 10 s)
bool red_ap_abierta(void);                       // la red propia no tiene contraseña
bool red_buscar(void);
const char *red_poner_ap(const char *ssid, const char *clave, bool siempre);   // NULL si va bien, o el error
int red_direcciones(char dirs[][48], int max);
void red_json(struct cJSON *r);
void red_estado(void);
void red_listar(void);                           // las redes de la última búsqueda (orden «wifi»)                           // por las respuestas (orden «estado»)

// sincro.c: los ajustes con las apps del ordenador, por el cable serie («ajustes …»)
bool sincro_orden(char *palabras[], int n);

// web.c: el servidor web (la app web, la pestaña Placa y el portal)
void web_iniciar(void);
