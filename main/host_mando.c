// Lado host del puente (Hito 2): lee el DualSense real por el MAX3421E con la pila de host de TinyUSB
// y hace de relé entre la PS5 y el mando: lo que la PS5 pide o escribe (informes de configuración y
// de autenticación) se le pasa al mando real, y lo que el mando contesta vuelve a la PS5.
#include <stdbool.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "tusb.h"
#include "puente.h"

#define HOST_RHPORT 1   // el device (PS5) va en el rhport 0 (OTG nativo); el host en el 1 (MAX3421E)

static const char *TAG = "host";

void max3421_glue_init(void);
bool max3421_int_pendiente(void);
bool max3421_presente(void);
bool max3421_vivo(void);
bool max3421_algo_enchufado(void);
void max3421_volcar_estado(uint32_t interrupciones);

// Último estado leído del mando real, ya convertido a mando_t (para el perfil, más adelante).
static mando_t mando_leido = { .dpad = DPAD_CENTRO, .lx = 128, .ly = 128, .rx = 128, .ry = 128 };

// --- Relé ---
// La PS5 habla con el lado device (tarea de TinyUSB device) y el mando real con este lado host (la
// tarea de host). Cada pila de TinyUSB se usa solo desde su tarea: las peticiones de la PS5 llegan
// por una cola a la tarea de host, que hace la transferencia con el mando y devuelve el resultado
// por otra cola. El lado device espera (bloqueado) a la respuesta, con un tiempo máximo.

typedef enum { REL_GET, REL_SET, REL_SALIDA } rel_clase_t;

typedef struct {
    rel_clase_t clase;
    uint8_t tipo;          // tipo de informe HID (feature, output...)
    uint8_t id;
    uint16_t largo;        // GET: bytes a pedir; SET/SALIDA: bytes en datos. Siempre con el ID incluido
    uint32_t num;          // para casar cada respuesta con su petición
    uint8_t datos[64];     // con el report ID en datos[0]
} rel_peticion_t;

typedef struct {
    uint32_t num;
    int largo;             // bytes recibidos (con el ID delante), o -1 si el mando no contestó
    uint8_t datos[64];
} rel_respuesta_t;

static TaskHandle_t tarea;
static QueueHandle_t cola_peticiones, cola_respuestas;
static volatile uint8_t mando_addr;    // 0 = no hay mando real montado
static uint8_t mando_idx, mando_itf;
static uint8_t buf_ctrl[64];           // datos de la transferencia de control en curso (tiene que durar)
static bool ocupado;                   // hay una transferencia de control en curso con el mando

// Informes de salida hacia el mando (vibración, luces, gatillos). En los juegos la PS5 manda muchísimos
// seguidos, y cada uno ocupa el bus del MAX3421E un rato en el que no se leen los sticks (se notaba como
// retraso al moverlo todo a la vez). Se guarda uno pendiente: si llega otro que toca los mismos campos
// (mismos bytes de «qué es válido»), sustituye al anterior; si toca otros, el anterior pasa a la cola.
static portMUX_TYPE cerrojo_salida = portMUX_INITIALIZER_UNLOCKED;
static uint8_t salida_pendiente[64];
static uint16_t salida_largo;
static bool hay_salida;
static volatile uint32_t n_salidas, n_salidas_juntadas, n_salidas_enviadas, n_salidas_perdidas, n_informes;

static bool mismos_campos(const uint8_t *a, const uint8_t *b, uint16_t largo)
{
    // Informe 0x02 por USB: byte 1 y 2 = valid_flag0/1, byte 39 = valid_flag2
    return a[0] == b[0] && a[1] == b[1] && a[2] == b[2] && (largo < 40 || a[39] == b[39]);
}

void host_mando_contadores(uint32_t c[5])
{
    c[0] = n_informes; c[1] = n_salidas; c[2] = n_salidas_juntadas; c[3] = n_salidas_enviadas; c[4] = n_salidas_perdidas;
    n_informes = n_salidas = n_salidas_juntadas = n_salidas_enviadas = n_salidas_perdidas = 0;
}

// Último informe de entrada crudo del mando real, para reenviarlo tal cual a la PS5.
static portMUX_TYPE cerrojo = portMUX_INITIALIZER_UNLOCKED;
static uint8_t informe_real[64];
static uint16_t informe_largo;
static bool informe_nuevo;

// Convierte un informe de entrada del DualSense (USB, informe 0x01) a nuestro mando_t.
// Mismo formato que lee app/dualsense.rs. El informe puede llegar con el report ID (0x01) delante o
// sin él, según cómo lo entregue la pila de host. Devuelve false si no es un 0x01 reconocible.
bool dualsense_parsear(const uint8_t *rep, uint16_t len, mando_t *m)
{
    const uint8_t *d;
    uint16_t n;
    if (len >= 11 && rep[0] == 0x01) { d = rep + 1; n = len - 1; }  // con report ID delante
    else { d = rep; n = len; }                                      // sin report ID
    if (n < 10) return false;

    m->lx = d[0]; m->ly = d[1]; m->rx = d[2]; m->ry = d[3];
    m->l2 = d[4]; m->r2 = d[5];
    // d[6] = contador de secuencia (no lo usamos)
    uint8_t hat = d[7] & 0x0F;
    m->dpad = hat <= DPAD_CENTRO ? hat : DPAD_CENTRO;

    uint16_t b = 0;
    if (d[7] & 0x10) b |= 1u << BTN_CUADRADO;
    if (d[7] & 0x20) b |= 1u << BTN_CRUZ;
    if (d[7] & 0x40) b |= 1u << BTN_CIRCULO;
    if (d[7] & 0x80) b |= 1u << BTN_TRIANGULO;
    if (d[8] & 0x01) b |= 1u << BTN_L1;
    if (d[8] & 0x02) b |= 1u << BTN_R1;
    if (d[8] & 0x04) b |= 1u << BTN_L2;
    if (d[8] & 0x08) b |= 1u << BTN_R2;
    if (d[8] & 0x10) b |= 1u << BTN_SHARE;
    if (d[8] & 0x20) b |= 1u << BTN_OPTIONS;
    if (d[8] & 0x40) b |= 1u << BTN_L3;
    if (d[8] & 0x80) b |= 1u << BTN_R3;
    if (d[9] & 0x01) b |= 1u << BTN_PS;
    if (d[9] & 0x02) b |= 1u << BTN_TACTIL;
    m->botones = b;
    return true;
}

// Prueba el parser con una captura real del DualSense (del propio mando del usuario, por USB).
// Esperado: sticks ~centro (lx=130 ly=123 rx=126 ry=131), gatillos 0, cruceta suelta (8), sin botones.
static void dualsense_autotest(void)
{
    static const uint8_t capt[] = { 0x01, 0x82, 0x7b, 0x7e, 0x83, 0x00, 0x00, 0xec, 0x08, 0x00, 0x00, 0x00 };
    mando_t m = { 0 };
    if (dualsense_parsear(capt, sizeof(capt), &m)) {
        ESP_LOGI(TAG, "autotest parser: lx=%u ly=%u rx=%u ry=%u l2=%u r2=%u dpad=%u botones=0x%04X",
                 m.lx, m.ly, m.rx, m.ry, m.l2, m.r2, m.dpad, m.botones);
    } else {
        ESP_LOGW(TAG, "autotest parser: informe no reconocido");
    }
}

// Diagnóstico provisional: el VBUS del MAX3421E se cablea al GPIO4 (en vez de a 5V) para ver si la
// placa lo trae unido a VCC (3,3 V). Se lee con pull-down y con pull-up: si cambia, está suelto.
#define PIN_SONDA_VBUS 4
static void sondear_vbus(void)
{
    gpio_config_t c = { .pin_bit_mask = 1ULL << PIN_SONDA_VBUS, .mode = GPIO_MODE_INPUT, .pull_down_en = 1 };
    gpio_config(&c);
    vTaskDelay(pdMS_TO_TICKS(5));
    int con_bajada = gpio_get_level(PIN_SONDA_VBUS);
    gpio_pulldown_dis(PIN_SONDA_VBUS);
    gpio_pullup_en(PIN_SONDA_VBUS);
    vTaskDelay(pdMS_TO_TICKS(5));
    int con_subida = gpio_get_level(PIN_SONDA_VBUS);
    gpio_pullup_dis(PIN_SONDA_VBUS);
    const char *veredicto = (con_bajada && con_subida)   ? "UNIDO A TENSIÓN (VBUS = VCC 3,3 V: hay que cortar la pista)"
                          : (!con_bajada && !con_subida) ? "UNIDO A MASA"
                          : (!con_bajada && con_subida)  ? "SUELTO (VBUS aislado de VCC)"
                                                         : "raro";
    ESP_LOGI(TAG, "sonda VBUS (GPIO%d): pull-down=%d pull-up=%d -> %s",
             PIN_SONDA_VBUS, con_bajada, con_subida, veredicto);
}

static void responder_fallo(uint32_t num)
{
    rel_respuesta_t r = { .num = num, .largo = -1 };
    xQueueSend(cola_respuestas, &r, 0);
}

static void fin_control(tuh_xfer_t *xfer)
{
    rel_respuesta_t r = { .num = (uint32_t)xfer->user_data, .largo = -1 };
    if (xfer->result == XFER_RESULT_SUCCESS) {
        r.largo = xfer->actual_len > sizeof(r.datos) ? (int)sizeof(r.datos) : (int)xfer->actual_len;
        memcpy(r.datos, buf_ctrl, r.largo);
    }
    ocupado = false;
    xQueueSend(cola_respuestas, &r, 0);
}

// En la tarea de host: hace con el mando real lo que pidió la PS5.
static void atender(const rel_peticion_t *p)
{
    if (!mando_addr) {
        if (p->clase != REL_SALIDA) responder_fallo(p->num);
        return;
    }
    if (p->clase == REL_SALIDA) {
        // Vibración, luces, gatillos: por el endpoint de salida, sin esperar respuesta.
        if (tuh_hid_send_ready(mando_addr, mando_idx) &&
            tuh_hid_send_report(mando_addr, mando_idx, p->id, p->datos + 1, p->largo - 1)) {
            n_salidas_enviadas++;
        } else {
            n_salidas_perdidas++;
        }
        return;
    }
    tusb_control_request_t req = {
        .bmRequestType_bit = {
            .recipient = TUSB_REQ_RCPT_INTERFACE,
            .type = TUSB_REQ_TYPE_CLASS,
            .direction = p->clase == REL_GET ? TUSB_DIR_IN : TUSB_DIR_OUT,
        },
        .bRequest = p->clase == REL_GET ? HID_REQ_CONTROL_GET_REPORT : HID_REQ_CONTROL_SET_REPORT,
        .wValue = tu_htole16(tu_u16(p->tipo, p->id)),
        .wIndex = tu_htole16(mando_itf),
        .wLength = tu_htole16(p->largo),
    };
    if (p->clase == REL_SET) memcpy(buf_ctrl, p->datos, p->largo);
    tuh_xfer_t x = {
        .daddr = mando_addr,
        .ep_addr = 0,
        .setup = &req,            // TinyUSB copia el setup; el buffer sí tiene que seguir vivo
        .buffer = buf_ctrl,
        .complete_cb = fin_control,
        .user_data = p->num,
    };
    ocupado = true;
    if (!tuh_control_xfer(&x)) {
        ocupado = false;
        responder_fallo(p->num);
    }
}

static void tarea_host(void *arg)
{
    sondear_vbus();
    max3421_glue_init();
    if (!max3421_presente()) {
        ESP_LOGW(TAG, "MAX3421E no detectado: el lado host queda desactivado. "
                      "Conecta la placa y reinicia para activarlo.");
        vTaskDelete(NULL);
        return;
    }
    // INT por nivel (bajo mientras haya algo pendiente) en vez del pulso de 10 us por defecto:
    // como el pin se sondea desde la tarea, un pulso tan corto se perdería.
    tuh_configure_param_t cfg = { .max3421 = { .max_nak = 1, .cpuctl = 0, .pinctl = 1u << 3 } };
    tuh_configure(HOST_RHPORT, TUH_CFGID_MAX3421, &cfg);
    if (!tuh_init(HOST_RHPORT)) {
        ESP_LOGE(TAG, "tuh_init falló aunque el MAX3421E responde");
        vTaskDelete(NULL);
        return;
    }
    ESP_LOGI(TAG, "Host USB por MAX3421E iniciado (rhport %d)", HOST_RHPORT);
    uint32_t interrupciones = 0;
    TickType_t ultimo_volcado = xTaskGetTickCount();
    TickType_t ultima_comprobacion = ultimo_volcado;
    TickType_t enchufado_desde = 0;
    while (true) {
        if (max3421_int_pendiente()) { tuh_int_handler(HOST_RHPORT, false); interrupciones++; }
        // tuh_task() a secas espera eventos para siempre, y los eventos salen de tuh_int_handler(),
        // que se llama en este mismo bucle: se quedaría bloqueado. Con timeout 0 solo procesa lo pendiente.
        tuh_task_ext(0, false);
        // Una petición de la PS5 cada vez: la siguiente espera a que acabe la transferencia en curso.
        rel_peticion_t p;
        if (!ocupado && xQueueReceive(cola_peticiones, &p, 0) == pdTRUE) atender(&p);
        // La salida pendiente, cuando el endpoint de salida del mando está libre
        else if (hay_salida && mando_addr && tuh_hid_send_ready(mando_addr, mando_idx)) {
            portENTER_CRITICAL(&cerrojo_salida);
            p.clase = REL_SALIDA;
            p.largo = salida_largo;
            memcpy(p.datos, salida_pendiente, salida_largo);
            p.id = p.datos[0];
            hay_salida = false;
            portEXIT_CRITICAL(&cerrojo_salida);
            atender(&p);
        }
        // Diagnóstico mientras no haya mando: cada 2 s, lo que ve el chip en el bus (se lee entre
        // llamadas de TinyUSB, en la misma tarea, así que no pisa ninguna transferencia).
        if (!mando_addr && xTaskGetTickCount() - ultimo_volcado > pdMS_TO_TICKS(2000)) {
            ultimo_volcado = xTaskGetTickCount();
            max3421_volcar_estado(interrupciones);
        }
        // Si el MAX3421E se ha reiniciado solo (pasa al enchufar el mando con la placa encendida), se
        // vuelve a poner en marcha el host entero; TinyUSB da por desconectado lo que hubiera.
        if (xTaskGetTickCount() - ultima_comprobacion > pdMS_TO_TICKS(250)) {
            ultima_comprobacion = xTaskGetTickCount();
            // Algo enchufado que no llega a montarse (visto: el mando contesta NAK a todo tras un
            // apagón): a los 3 s se reinicia el host, que hace un reset del bus y lo vuelve a enumerar.
            bool atascado = false;
            if (!mando_addr && max3421_algo_enchufado()) {
                if (!enchufado_desde) enchufado_desde = xTaskGetTickCount();
                atascado = xTaskGetTickCount() - enchufado_desde > pdMS_TO_TICKS(3000);
            } else {
                enchufado_desde = 0;
            }
            bool vivo = max3421_vivo();
            if (!vivo || atascado) {
                ESP_LOGW(TAG, "%s", vivo ? "Hay algo en el USB-A pero no se conecta: reinicio el host"
                                   : "El MAX3421E se ha reiniciado: vuelvo a ponerlo en marcha");
                enchufado_desde = 0;
                tuh_deinit(HOST_RHPORT);
                ocupado = false;
                if (max3421_presente() && tuh_init(HOST_RHPORT)) ESP_LOGI(TAG, "Host USB otra vez en marcha");
            }
        }
        // Espera 1 ms, o menos si el lado device deja una petición (nos avisa con una notificación).
        ulTaskNotifyTake(pdTRUE, 1);
    }
}

void host_mando_iniciar(void)
{
    dualsense_autotest();   // valida el parser con la captura real (se verá en el log al arrancar)
    cola_peticiones = xQueueCreate(8, sizeof(rel_peticion_t));
    cola_respuestas = xQueueCreate(4, sizeof(rel_respuesta_t));
    xTaskCreatePinnedToCore(tarea_host, "host", 4096, NULL, 9, &tarea, 1);   // núcleo 1, con el mando
}

// --- Lo que usa el lado device (usb_ps4.c), desde la tarea de TinyUSB device ---

bool host_mando_listo(void) { return mando_addr != 0; }

// Manda la petición a la tarea de host y espera su respuesta. Devuelve los bytes recibidos (con el
// report ID delante) o -1 si el mando no contestó a tiempo.
static int relevar(rel_peticion_t *p, uint8_t *resp, uint32_t espera_ms)
{
    static uint32_t contador;
    p->num = ++contador;
    rel_respuesta_t r;
    while (xQueueReceive(cola_respuestas, &r, 0) == pdTRUE) {}   // restos de peticiones caducadas
    if (xQueueSend(cola_peticiones, p, 0) != pdTRUE) return -1;
    xTaskNotifyGive(tarea);
    TickType_t inicio = xTaskGetTickCount(), limite = pdMS_TO_TICKS(espera_ms);
    while (xTaskGetTickCount() - inicio < limite) {
        TickType_t queda = limite - (xTaskGetTickCount() - inicio);
        if (xQueueReceive(cola_respuestas, &r, queda) != pdTRUE) break;
        if (r.num != p->num) continue;
        if (resp && r.largo > 0) memcpy(resp, r.datos, r.largo);
        return r.largo;
    }
    return -1;
}

// GET al mando real. largo = bytes que pidió la PS5 (con el ID). resp recibe la respuesta con el ID.
int host_mando_get(uint8_t tipo, uint8_t id, uint8_t *resp, uint16_t largo)
{
    if (!mando_addr || largo == 0 || largo > 64) return -1;
    rel_peticion_t p = { .clase = REL_GET, .tipo = tipo, .id = id, .largo = largo };
    return relevar(&p, resp, 250);
}

// SET al mando real. datos llega SIN el report ID (TinyUSB device lo quita); aquí se vuelve a poner.
int host_mando_set(uint8_t tipo, uint8_t id, const uint8_t *datos, uint16_t largo)
{
    if (!mando_addr || largo + 1 > 64) return -1;
    rel_peticion_t p = { .clase = REL_SET, .tipo = tipo, .id = id, .largo = largo + 1 };
    p.datos[0] = id;
    memcpy(p.datos + 1, datos, largo);
    return relevar(&p, NULL, 250);
}

// Informe de salida de la PS5 (vibración, luces, gatillos), con el ID en rep[0]. No espera.
void host_mando_salida(const uint8_t *rep, uint16_t largo)
{
    if (!mando_addr || largo < 2 || largo > 64) return;
    n_salidas++;
    rel_peticion_t p = { .clase = REL_SALIDA, .largo = 0 };
    portENTER_CRITICAL(&cerrojo_salida);
    if (hay_salida && salida_largo == largo && mismos_campos(salida_pendiente, rep, largo)) {
        n_salidas_juntadas++;                       // sustituye a la pendiente
    } else if (hay_salida) {
        p.largo = salida_largo;                     // la pendiente toca otros campos: a la cola
        memcpy(p.datos, salida_pendiente, salida_largo);
        p.id = p.datos[0];
    }
    memcpy(salida_pendiente, rep, largo);
    salida_largo = largo;
    hay_salida = true;
    portEXIT_CRITICAL(&cerrojo_salida);
    if (p.largo && xQueueSend(cola_peticiones, &p, 0) != pdTRUE) n_salidas_perdidas++;
    xTaskNotifyGive(tarea);
}

// Copia el último informe de entrada del mando real si hay uno nuevo desde la última llamada.
bool host_mando_informe(uint8_t *inf, uint16_t *largo)
{
    bool hay = false;
    portENTER_CRITICAL(&cerrojo);
    if (informe_nuevo) {
        memcpy(inf, informe_real, informe_largo);
        *largo = informe_largo;
        informe_nuevo = false;
        hay = true;
    }
    portEXIT_CRITICAL(&cerrojo);
    return hay;
}

// El último estado leído del mando real. Lo usará el input del Hito 2 (pasarlo por el perfil y
// mandarlo a la PS5). Centro mientras no haya mando conectado al host.
void host_mando_estado(mando_t *salida)
{
    *salida = mando_leido;
}

// --- Callbacks de la pila de host de TinyUSB ---

void tuh_mount_cb(uint8_t daddr)
{
    uint16_t vid = 0, pid = 0;
    tuh_vid_pid_get(daddr, &vid, &pid);
    ESP_LOGI(TAG, "Conectado al host: addr %u, VID %04X PID %04X%s",
             daddr, vid, pid, (vid == 0x054C) ? "  <- mando de Sony" : "");
}

void tuh_umount_cb(uint8_t daddr)
{
    ESP_LOGI(TAG, "Desconectado del host: addr %u", daddr);
}

void tuh_hid_mount_cb(uint8_t dev_addr, uint8_t idx, const uint8_t *report_desc, uint16_t desc_len)
{
    uint16_t vid = 0, pid = 0;
    tuh_vid_pid_get(dev_addr, &vid, &pid);
    tuh_itf_info_t info;
    uint8_t itf = tuh_hid_itf_get_info(dev_addr, idx, &info) ? info.desc.bInterfaceNumber : 0;
    ESP_LOGI(TAG, "HID montado: addr %u idx %u interfaz %u (descriptor de %u bytes)",
             dev_addr, idx, itf, desc_len);
    if (vid == 0x054C && !mando_addr) {
        // El relé ya puede pasarle al mando lo que pida la PS5
        mando_idx = idx;
        mando_itf = itf;
        ocupado = false;
        mando_addr = dev_addr;
        ESP_LOGI(TAG, "DualSense listo para el relé (PID %04X)", pid);
    }
    tuh_hid_receive_report(dev_addr, idx);   // empezamos a recibir sus informes de entrada
}

void tuh_hid_umount_cb(uint8_t dev_addr, uint8_t idx)
{
    ESP_LOGI(TAG, "HID desmontado: addr %u idx %u", dev_addr, idx);
    if (dev_addr == mando_addr && idx == mando_idx) mando_addr = 0;
}

void tuh_hid_report_received_cb(uint8_t dev_addr, uint8_t idx, const uint8_t *report, uint16_t len)
{
    n_informes++;
    if (dev_addr == mando_addr && idx == mando_idx && len > 1 && len <= sizeof(informe_real)) {
        // Crudo, para reenviarlo tal cual a la PS5 (con giroscopio, panel táctil, etc.)
        portENTER_CRITICAL(&cerrojo);
        memcpy(informe_real, report, len);
        informe_largo = len;
        informe_nuevo = true;
        portEXIT_CRITICAL(&cerrojo);
    }
    // Y convertido a mando_t, para cuando el perfil (anti-recoil, etc.) corra en la placa
    mando_t m = { .dpad = DPAD_CENTRO, .lx = 128, .ly = 128, .rx = 128, .ry = 128 };
    if (dualsense_parsear(report, len, &m)) {
        mando_leido = m;
    }
    tuh_hid_receive_report(dev_addr, idx);   // pedir el siguiente informe
}
