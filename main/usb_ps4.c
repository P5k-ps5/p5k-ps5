// El USB nativo del ESP32-S3 se presenta como un mando de PS4 (DualShock 4).
// Descriptor e informes basados en GP2040-CE (licencia MIT, OpenStickCommunity):
// https://github.com/OpenStickCommunity/GP2040-CE/blob/main/headers/drivers/ps4/PS4Descriptors.h
//
// En modo Mac se añade un puerto serie (CDC) por el mismo cable para mandar órdenes.
// En modo consola solo va el mando, para que el P5Mate vea un mando normal.

#include <string.h>
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "tinyusb.h"
#include "tusb_cdc_acm.h"
#include "puente.h"
#include "dualsense_descriptores.h"
#include "motor.h"

static const char *TAG = "usb";

#define VID_SONY  0x054C
#define PID_DS4   0x09CC   // DualShock 4 de segunda versión

#define EP_HID_IN    0x81
#define EP_HID_OUT   0x03
#define EP_CDC_AVISO 0x82
#define EP_CDC_OUT   0x04
#define EP_CDC_IN    0x84

static const uint8_t descriptor_informe[] = {
    0x05, 0x01, 0x09, 0x05, 0xA1, 0x01,             // Gamepad
    0x85, 0x01,                                     //   ID 1: entrada
    0x09, 0x30, 0x09, 0x31, 0x09, 0x32, 0x09, 0x35, //   X, Y, Z, Rz (sticks)
    0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x04, 0x81, 0x02,
    0x09, 0x39, 0x15, 0x00, 0x25, 0x07, 0x35, 0x00, 0x46, 0x3B, 0x01, // cruceta
    0x65, 0x14, 0x75, 0x04, 0x95, 0x01, 0x81, 0x42,
    0x65, 0x00, 0x05, 0x09, 0x19, 0x01, 0x29, 0x0E, // 14 botones
    0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x0E, 0x81, 0x02,
    0x06, 0x00, 0xFF, 0x09, 0x20, 0x75, 0x06, 0x95, 0x01, 0x81, 0x02, // contador
    0x05, 0x01, 0x09, 0x33, 0x09, 0x34,             // Rx, Ry (gatillos)
    0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x02, 0x81, 0x02,
    0x06, 0x00, 0xFF, 0x09, 0x21, 0x95, 0x36, 0x81, 0x02, // 54 bytes: sensores y táctil
    0x85, 0x05, 0x09, 0x22, 0x95, 0x1F, 0x91, 0x02, //   ID 5: salida (vibración y luz)
    0x85, 0x03, 0x0A, 0x21, 0x27, 0x95, 0x2F, 0xB1, 0x02, // ID 3: qué tipo de mando es
    0x85, 0x02, 0x09, 0x24, 0x95, 0x24, 0xB1, 0x02, //   ID 2: calibración
    0x85, 0x08, 0x09, 0x25, 0x95, 0x03, 0xB1, 0x02,
    0x85, 0x10, 0x09, 0x26, 0x95, 0x04, 0xB1, 0x02,
    0x85, 0x11, 0x09, 0x27, 0x95, 0x02, 0xB1, 0x02,
    0x85, 0x12, 0x06, 0x02, 0xFF, 0x09, 0x21, 0x95, 0x0F, 0xB1, 0x02, // ID 0x12: MAC
    0x85, 0x13, 0x09, 0x22, 0x95, 0x16, 0xB1, 0x02,
    0x85, 0x14, 0x06, 0x05, 0xFF, 0x09, 0x20, 0x95, 0x10, 0xB1, 0x02,
    0x85, 0x15, 0x09, 0x21, 0x95, 0x2C, 0xB1, 0x02,
    0x06, 0x80, 0xFF,
    0x85, 0x80, 0x09, 0x20, 0x95, 0x06, 0xB1, 0x02,
    0x85, 0x81, 0x09, 0x21, 0x95, 0x06, 0xB1, 0x02,
    0x85, 0x82, 0x09, 0x22, 0x95, 0x05, 0xB1, 0x02,
    0x85, 0x83, 0x09, 0x23, 0x95, 0x01, 0xB1, 0x02,
    0x85, 0x84, 0x09, 0x24, 0x95, 0x04, 0xB1, 0x02,
    0x85, 0x85, 0x09, 0x25, 0x95, 0x06, 0xB1, 0x02,
    0x85, 0x86, 0x09, 0x26, 0x95, 0x06, 0xB1, 0x02,
    0x85, 0x87, 0x09, 0x27, 0x95, 0x23, 0xB1, 0x02,
    0x85, 0x88, 0x09, 0x28, 0x95, 0x22, 0xB1, 0x02,
    0x85, 0x89, 0x09, 0x29, 0x95, 0x02, 0xB1, 0x02,
    0x85, 0x90, 0x09, 0x30, 0x95, 0x05, 0xB1, 0x02,
    0x85, 0x91, 0x09, 0x31, 0x95, 0x03, 0xB1, 0x02,
    0x85, 0x92, 0x09, 0x32, 0x95, 0x03, 0xB1, 0x02,
    0x85, 0x93, 0x09, 0x33, 0x95, 0x0C, 0xB1, 0x02,
    0x85, 0xA0, 0x09, 0x40, 0x95, 0x06, 0xB1, 0x02,
    0x85, 0xA1, 0x09, 0x41, 0x95, 0x01, 0xB1, 0x02,
    0x85, 0xA2, 0x09, 0x42, 0x95, 0x01, 0xB1, 0x02,
    0x85, 0xA3, 0x09, 0x43, 0x95, 0x30, 0xB1, 0x02, //   ID 0xA3: versión del firmware
    0x85, 0xA4, 0x09, 0x44, 0x95, 0x0D, 0xB1, 0x02,
    0x85, 0xA5, 0x09, 0x45, 0x95, 0x15, 0xB1, 0x02,
    0x85, 0xA6, 0x09, 0x46, 0x95, 0x15, 0xB1, 0x02,
    0x85, 0xA7, 0x09, 0x4A, 0x95, 0x01, 0xB1, 0x02,
    0x85, 0xA8, 0x09, 0x4B, 0x95, 0x01, 0xB1, 0x02,
    0x85, 0xA9, 0x09, 0x4C, 0x95, 0x08, 0xB1, 0x02,
    0x85, 0xAA, 0x09, 0x4E, 0x95, 0x01, 0xB1, 0x02,
    0x85, 0xAB, 0x09, 0x4F, 0x95, 0x39, 0xB1, 0x02,
    0x85, 0xAC, 0x09, 0x50, 0x95, 0x39, 0xB1, 0x02,
    0x85, 0xAD, 0x09, 0x51, 0x95, 0x0B, 0xB1, 0x02,
    0x85, 0xAE, 0x09, 0x52, 0x95, 0x01, 0xB1, 0x02,
    0x85, 0xAF, 0x09, 0x53, 0x95, 0x02, 0xB1, 0x02,
    0x85, 0xB0, 0x09, 0x54, 0x95, 0x3F, 0xB1, 0x02,
    0xC0,
    0x06, 0xF0, 0xFF, 0x09, 0x40, 0xA1, 0x01,       // Autenticación de PS4 (F0..F3).
    0x85, 0xF0, 0x09, 0x47, 0x95, 0x3F, 0xB1, 0x02, // No la contestamos: de eso se
    0x85, 0xF1, 0x09, 0x48, 0x95, 0x3F, 0xB1, 0x02, // encarga el P5Mate con la consola.
    0x85, 0xF2, 0x09, 0x49, 0x95, 0x0F, 0xB1, 0x02,
    0x85, 0xF3, 0x0A, 0x01, 0x47, 0x95, 0x07, 0xB1, 0x02,
    0xC0,
};

// Respuestas a las peticiones de configuración (sin el byte de ID)
static const uint8_t calibracion_0x02[] = {
    0xfe, 0xff, 0x0e, 0x00, 0x04, 0x00, 0xd4, 0x22, 0x2a, 0xdd, 0xbb, 0x22,
    0x5e, 0xdd, 0x81, 0x22, 0x84, 0xdd, 0x1c, 0x02, 0x1c, 0x02, 0x85, 0x1f,
    0xb0, 0xe0, 0xc6, 0x20, 0xb5, 0xe0, 0xb1, 0x20, 0x83, 0xdf, 0x0c, 0x00,
};
static const uint8_t definicion_0x03[] = {   // byte 4 = 0x00: mando normal
    0x21, 0x27, 0x04, 0xcf, 0x00, 0x2c, 0x56, 0x08, 0x00, 0x3d, 0x00, 0xe8,
    0x03, 0x04, 0x00, 0xff, 0x7f, 0x0d, 0x0d, 0x00, 0x00, 0x00, 0x00, 0x0d,
    0x84, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};
static const uint8_t mac_0x12[] = {
    0x5e, 0xe5, 0x32, 0xa0, 0x04, 0xe5,   // MAC del "mando" (inventada)
    0x08, 0x25, 0x00,                     // clase Bluetooth
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,   // MAC de la consola
};
static const uint8_t version_0xa3[] = {
    0x4a, 0x75, 0x6e, 0x20, 0x20, 0x39, 0x20, 0x32, 0x30, 0x31, 0x37, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x31, 0x32, 0x3a, 0x33, 0x36, 0x3a, 0x34, 0x31,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x08, 0xb4,
    0x01, 0x00, 0x00, 0x00, 0x07, 0xa0, 0x10, 0x20, 0x00, 0xa0, 0x02, 0x00,
};

static tusb_desc_device_t descriptor_dispositivo = {
    .bLength = sizeof(tusb_desc_device_t),
    .bDescriptorType = TUSB_DESC_DEVICE,
    .bcdUSB = 0x0200,
    .bMaxPacketSize0 = CFG_TUD_ENDPOINT0_SIZE,
    .idVendor = VID_SONY,
    .idProduct = PID_DS4,
    .bcdDevice = 0x0100,
    .iManufacturer = 1,
    .iProduct = 2,
    .iSerialNumber = 0,
    .bNumConfigurations = 1,
};

static const char *textos[] = {
    "\x09\x04",                         // idioma: inglés
    "Sony Interactive Entertainment",
    "Wireless Controller",
    "",
    "Puente de mando (serie)",
};

// Modo DualSense (PS5): mismos textos que un DualSense real
static const char *textos_ds[] = {
    "\x09\x04",
    "Sony Interactive Entertainment",
    "DualSense Wireless Controller",
};

// Configuración DualSense: de momento solo la interfaz HID (el mando). Las interfaces de audio del
// DualSense real van en el Hito siguiente; aquí probamos si la PS5 arranca la autenticación contra
// un DualSense solo-HID. attr 0xC0 = self-powered (como el real), 500 mA.
#define LARGO_DUALSENSE (TUD_CONFIG_DESC_LEN + TUD_HID_INOUT_DESC_LEN)
static const uint8_t config_dualsense[] = {
    TUD_CONFIG_DESCRIPTOR(1, 1, 0, LARGO_DUALSENSE, 0xC0, 500),
    TUD_HID_INOUT_DESCRIPTOR(0, 0, HID_ITF_PROTOCOL_NONE, sizeof(ds_descriptor_informe),
                             EP_HID_OUT, EP_HID_IN, 64, 1),
};

#define LARGO_SOLO_MANDO (TUD_CONFIG_DESC_LEN + TUD_HID_INOUT_DESC_LEN)
#define LARGO_CON_SERIE  (LARGO_SOLO_MANDO + TUD_CDC_DESC_LEN)

static const uint8_t config_solo_mando[] = {
    TUD_CONFIG_DESCRIPTOR(1, 1, 0, LARGO_SOLO_MANDO, 0x80, 500),
    TUD_HID_INOUT_DESCRIPTOR(0, 0, HID_ITF_PROTOCOL_NONE, sizeof(descriptor_informe),
                             EP_HID_OUT, EP_HID_IN, 64, 1),
};

static const uint8_t config_con_serie[] = {
    TUD_CONFIG_DESCRIPTOR(1, 3, 0, LARGO_CON_SERIE, 0x80, 500),
    TUD_HID_INOUT_DESCRIPTOR(0, 0, HID_ITF_PROTOCOL_NONE, sizeof(descriptor_informe),
                             EP_HID_OUT, EP_HID_IN, 64, 1),
    TUD_CDC_DESCRIPTOR(1, 4, EP_CDC_AVISO, 8, EP_CDC_OUT, EP_CDC_IN, 64),
};

static bool hay_serie;
static modo_t modo_usb = MODO_MAC;
static volatile uint32_t peticiones;
static volatile uint32_t veces_por_id[256];
static uint8_t vibracion_fuerte, vibracion_suave;
// Último color de la barra de luz que puso la PS5 (modo dualsense), para devolverlo tras un destello
static portMUX_TYPE cerrojo_luz = portMUX_INITIALIZER_UNLOCKED;
static uint8_t luz_ps5[3];
static bool hay_luz_ps5;

// --- Lo que pide TinyUSB ---

uint8_t const *tud_hid_descriptor_report_cb(uint8_t instancia)
{
    return modo_usb == MODO_DUALSENSE ? ds_descriptor_informe : descriptor_informe;
}

static uint16_t copiar(uint8_t *destino, uint16_t cabe, const uint8_t *origen, uint16_t largo)
{
    if (largo > cabe) largo = cabe;
    memcpy(destino, origen, largo);
    return largo;
}

uint16_t tud_hid_get_report_cb(uint8_t instancia, uint8_t id, hid_report_type_t tipo,
                               uint8_t *buffer, uint16_t cabe)
{
    peticiones++;
    if (veces_por_id[id]++ == 0) {
        ESP_LOGI(TAG, "El aparato pide el informe 0x%02X (tipo %d, %u bytes)", id, tipo, cabe);
    }
    // Ojo: TinyUSB ya pone el report ID delante de la respuesta (y descuenta ese byte de "cabe");
    // aquí solo va lo que sigue al ID.
    if (modo_usb == MODO_DUALSENSE) {
        // Con el DualSense real conectado al host, se lo preguntamos a él (relé, Hito 2).
        if (host_mando_listo()) {
            uint8_t resp[64];
            int64_t t0 = esp_timer_get_time();
            int n = host_mando_get(tipo, id, resp, cabe + 1);
            unsigned long us = (unsigned long)(esp_timer_get_time() - t0);
            if (n > 1) {
                const uint8_t *datos = resp[0] == id ? resp + 1 : resp;
                uint16_t largo = resp[0] == id ? n - 1 : n;
                ESP_LOGI(TAG, "PS5 GET 0x%02X -> mando real: %d bytes en %lu us", id, n, us);
                if (id == 0x81 || id == 0x82 || id == 0x83 || id == 0x05 || id == 0x20 || id == 0x0B) {
                    char hex[100]; int k = 0;
                    for (int i = 0; i < n && i < 32; i++) k += sprintf(hex + k, "%02x ", resp[i]);
                    ESP_LOGI(TAG, "    respuesta: %s", hex);
                }
                return copiar(buffer, cabe, datos, largo);
            }
            ESP_LOGW(TAG, "PS5 GET 0x%02X -> el mando real no contestó (%lu us)", id, us);
            if (id >= 0xF0 && id <= 0xF5) return 0;   // autenticación: sin mando no hay respuesta
        } else {
            ESP_LOGI(TAG, "PS5 GET 0x%02X (%u bytes)", id, cabe);
        }
        if (tipo != HID_REPORT_TYPE_FEATURE) return 0;
        // Sin mando real: feature reports capturados del DualSense (empiezan por el ID, que se salta).
        for (size_t i = 0; i < sizeof(ds_features) / sizeof(ds_features[0]); i++) {
            if (ds_features[i].id == id) {
                return copiar(buffer, cabe, ds_features[i].datos + 1, ds_features[i].largo - 1);
            }
        }
        // La autenticación (0xF0..0xF5) no se puede contestar sin el mando real.
        if (id >= 0xF0 && id <= 0xF5) return 0;
        // Cualquier otro report que la PS5 pida y no tengamos: ceros de la longitud pedida (muchos
        // del DualSense son ceros), en vez de un STALL que para a la consola.
        memset(buffer, 0, cabe);
        return cabe;
    }
    if (tipo != HID_REPORT_TYPE_FEATURE) return 0;
    switch (id) {
    case 0x02: return copiar(buffer, cabe, calibracion_0x02, sizeof(calibracion_0x02));
    case 0x03: return copiar(buffer, cabe, definicion_0x03, sizeof(definicion_0x03));
    case 0x12: return copiar(buffer, cabe, mac_0x12, sizeof(mac_0x12));
    case 0xA3: return copiar(buffer, cabe, version_0xa3, sizeof(version_0xa3));
    default:   return 0;   // 0xF0..0xF3 (autenticación) y el resto: no contestamos
    }
}

void tud_hid_set_report_cb(uint8_t instancia, uint8_t id, hid_report_type_t tipo,
                           uint8_t const *buffer, uint16_t largo)
{
    // DualSense: el informe de salida de la PS5 (vibración, luces, gatillos) llega por el endpoint de
    // salida, entero y con su ID delante. Se le pasa al mando real sin esperar.
    if (modo_usb == MODO_DUALSENSE && id == 0) {
        host_mando_salida(buffer, largo);
        // Informe 0x02 (USB): valid_flag1 en el byte 2 (0x04 = barra de luz) y el color en los bytes 45-47
        if (largo >= 48 && buffer[0] == 0x02 && (buffer[2] & 0x04)) {
            portENTER_CRITICAL(&cerrojo_luz);
            memcpy(luz_ps5, buffer + 45, 3);
            hay_luz_ps5 = true;
            portEXIT_CRITICAL(&cerrojo_luz);
        }
        return;
    }
    // Por el endpoint de salida llega el informe 5 entero (con su ID delante)
    if (id == 0 && largo >= 6 && buffer[0] == 0x05) {
        if (buffer[4] != vibracion_suave || buffer[5] != vibracion_fuerte) {
            vibracion_suave = buffer[4];
            vibracion_fuerte = buffer[5];
            ESP_LOGI(TAG, "Vibración: fuerte %u, suave %u", vibracion_fuerte, vibracion_suave);
        }
        return;
    }
    // En modo DualSense, volcamos lo que la PS5 nos escribe (SET), con su contenido, para entender
    // la secuencia. Si aparece 0xF0, es el reto de autenticación.
    if (modo_usb == MODO_DUALSENSE) {
        char hex[49]; int k = 0;
        for (int i = 0; i < largo && i < 16; i++) k += sprintf(hex + k, "%02x ", buffer[i]);   // (49 = 16 × 3 + 1)
        ESP_LOGW(TAG, "PS5 SET 0x%02X (%u bytes): %s%s", id, largo, hex,
                 id == 0xF0 ? " <- RETO DE AUTENTICACIÓN" : "");
        // Con el DualSense real conectado, se lo pasamos (relé). Se espera a que lo acepte para que
        // un GET posterior de la PS5 llegue al mando después de este SET, en orden.
        if (host_mando_listo()) {
            int64_t t0 = esp_timer_get_time();
            int n = host_mando_set(tipo, id, buffer, largo);
            unsigned long us = (unsigned long)(esp_timer_get_time() - t0);
            if (n >= 0) ESP_LOGI(TAG, "  -> mando real: aceptado en %lu us", us);
            else        ESP_LOGW(TAG, "  -> el mando real no lo aceptó (%lu us)", us);
        }
    }
    peticiones++;
    if (veces_por_id[id]++ == 0) {
        ESP_LOGI(TAG, "El aparato envía el informe 0x%02X (tipo %d, %u bytes)", id, tipo, largo);
    }
}

void tud_mount_cb(void)   { ESP_LOGI(TAG, "Conectado: el aparato ya nos ve como mando"); }
void tud_umount_cb(void)  { ESP_LOGI(TAG, "Desconectado"); }

// --- Informes del mando ---

static void construir_informe(uint8_t *inf, const mando_t *m, uint8_t contador, uint16_t tiempo)
{
    memset(inf, 0, 64);
    inf[0] = 0x01;
    inf[1] = m->lx;
    inf[2] = m->ly;
    inf[3] = m->rx;
    inf[4] = m->ry;
    inf[5] = (m->dpad & 0x0F) | (uint8_t)((m->botones & 0x0F) << 4);
    inf[6] = (uint8_t)(m->botones >> 4);
    inf[7] = (uint8_t)((m->botones >> 12) & 0x03) | (uint8_t)(contador << 2);
    inf[8] = m->l2;
    inf[9] = m->r2;
    inf[10] = (uint8_t)tiempo;
    inf[11] = (uint8_t)(tiempo >> 8);
    inf[29] = 0x1B;        // batería llena y con cable
    // Panel táctil sin tocar (bit 7 = 1 en el byte de cada dedo). La consola lee un paquete en el byte 33
    // (cuántos hay), 34 (contador) y los dedos en 35 y 39, como el DualShock 4 de verdad; con 0 ahí cree
    // que hay dos dedos apoyados en la esquina (sale un círculo y el teclado en pantalla salta a esa tecla).
    // 34 y 38 también a 0x80: son los dedos si se cuenta como GP2040-CE, así vale de las dos formas.
    inf[33] = 0x01;
    inf[34] = 0x80;
    inf[35] = 0x80;
    inf[38] = 0x80;
    inf[39] = 0x80;
}

// Informe de entrada del DualSense (PS5): informe 0x01 de 64 bytes, con una distribución distinta
// a la del DS4. Coincide con lo que lee app/dualsense.rs de un mando real.
static void construir_informe_dualsense(uint8_t *inf, const mando_t *m, uint8_t contador)
{
    memset(inf, 0, 64);
    inf[0] = 0x01;
    inf[1] = m->lx;
    inf[2] = m->ly;
    inf[3] = m->rx;
    inf[4] = m->ry;
    inf[5] = m->l2;
    inf[6] = m->r2;
    inf[7] = contador;                 // contador de secuencia del DualSense
    uint8_t b0 = (uint8_t)(m->dpad & 0x0F);
    if (m->botones & (1u << BTN_CUADRADO))  b0 |= 0x10;
    if (m->botones & (1u << BTN_CRUZ))      b0 |= 0x20;
    if (m->botones & (1u << BTN_CIRCULO))   b0 |= 0x40;
    if (m->botones & (1u << BTN_TRIANGULO)) b0 |= 0x80;
    inf[8] = b0;
    uint8_t b1 = 0;
    if (m->botones & (1u << BTN_L1))      b1 |= 0x01;
    if (m->botones & (1u << BTN_R1))      b1 |= 0x02;
    if (m->botones & (1u << BTN_L2))      b1 |= 0x04;
    if (m->botones & (1u << BTN_R2))      b1 |= 0x08;
    if (m->botones & (1u << BTN_SHARE))   b1 |= 0x10;
    if (m->botones & (1u << BTN_OPTIONS)) b1 |= 0x20;
    if (m->botones & (1u << BTN_L3))      b1 |= 0x40;
    if (m->botones & (1u << BTN_R3))      b1 |= 0x80;
    inf[9] = b1;
    uint8_t b2 = 0;
    if (m->botones & (1u << BTN_PS))     b2 |= 0x01;
    if (m->botones & (1u << BTN_TACTIL)) b2 |= 0x02;
    inf[10] = b2;
    inf[11] = contador;                // segundo contador (vendor)
    inf[53] = 0x08;                    // batería: un nivel plausible (cosmético para el Hito 1)
}

// --- El mando real (por el MAX3421E) pasa por el motor ---

// Salida del motor (botones de modelo::Boton) -> mando_t: los 14 primeros van en el mismo orden que BTN_*;
// la cruceta, de cuatro botones a su posición (0 arriba, en sentido horario; 8 suelta)
static void motor_a_mando(const motor_estado_t *e, mando_t *m)
{
    bool ar = e->botones & (1u << MB_ARRIBA), de = e->botones & (1u << MB_DERECHA);
    bool ab = e->botones & (1u << MB_ABAJO), iz = e->botones & (1u << MB_IZQUIERDA);
    m->botones = (uint16_t)(e->botones & 0x3FFF);
    m->dpad = (ar && de) ? 1 : (de && ab) ? 3 : (ab && iz) ? 5 : (iz && ar) ? 7
            : ar ? 0 : de ? 2 : ab ? 4 : iz ? 6 : DPAD_CENTRO;
    m->lx = e->lx; m->ly = e->ly; m->rx = e->rx; m->ry = e->ry;
    m->l2 = e->l2; m->r2 = e->r2;
}

// La salida del motor encima del informe real del DualSense: sticks, gatillos y botones del motor; lo demás
// (giroscopio, panel táctil, batería, contadores) tal cual llegó del mando
static void motor_sobre_dualsense(uint8_t *inf, const motor_estado_t *e)
{
    uint8_t *d = inf + 1;
    mando_t m;
    motor_a_mando(e, &m);
    d[0] = e->lx; d[1] = e->ly; d[2] = e->rx; d[3] = e->ry;
    d[4] = e->l2; d[5] = e->r2;
    uint8_t b0 = m.dpad & 0x0F;
    if (e->botones & (1u << MB_CUADRADO))  b0 |= 0x10;
    if (e->botones & (1u << MB_X))         b0 |= 0x20;
    if (e->botones & (1u << MB_CIRCULO))   b0 |= 0x40;
    if (e->botones & (1u << MB_TRIANGULO)) b0 |= 0x80;
    d[7] = b0;
    uint8_t b1 = 0;
    for (int i = 0; i < 8; i++) if (e->botones & (1u << (MB_L1 + i))) b1 |= 1u << i;   // L1 R1 L2 R2 Share Options L3 R3
    d[8] = b1;
    uint8_t b2 = d[9] & ~0x07;
    if (e->botones & (1u << MB_PS))        b2 |= 0x01;
    if (e->botones & (1u << MB_TACTIL))    b2 |= 0x02;
    if (e->botones & (1u << MB_SILENCIAR)) b2 |= 0x04;
    d[9] = b2;
}

// Luz del mando real: destello al encender/apagar el anti-recoil o la ayuda (como la app de escritorio) y,
// en modo consola, el color del perfil. En modo dualsense la luz es de la PS5: tras el destello se le
// devuelve el último color que puso.
static void luz_del_mando(int64_t t, bool reiniciar)
{
    static bool preparada;
    static int64_t restaurar, mirado;
    static uint32_t color = 0xFFFFFFFF;
    if (reiniciar) { preparada = false; restaurar = 0; color = 0xFFFFFFFF; return; }
    uint8_t luz[64], rgb[3];
    if (motor_destello(rgb)) {
        size_t n = motor_informe_luz(rgb[0], rgb[1], rgb[2], !preparada, luz, sizeof(luz));
        if (n) { host_mando_salida(luz, n); preparada = true; restaurar = t + 400000; }
    }
    if (restaurar && t >= restaurar) {
        restaurar = 0;
        if (modo_usb == MODO_DUALSENSE) {
            uint8_t c[3];
            bool hay;
            portENTER_CRITICAL(&cerrojo_luz);
            memcpy(c, luz_ps5, 3);
            hay = hay_luz_ps5;
            portEXIT_CRITICAL(&cerrojo_luz);
            size_t n = hay ? motor_informe_luz(c[0], c[1], c[2], false, luz, sizeof(luz)) : 0;
            if (n) host_mando_salida(luz, n);
        }
        color = 0xFFFFFFFF;                  // en modo consola, se vuelve a poner el color del perfil
    }
    if (modo_usb == MODO_CONSOLA && !restaurar && t - mirado > 250000) {
        mirado = t;
        if (motor_color(rgb)) {
            uint32_t v = ((uint32_t)rgb[0] << 16) | (rgb[1] << 8) | rgb[2];
            size_t n = v != color ? motor_informe_luz(rgb[0], rgb[1], rgb[2], !preparada, luz, sizeof(luz)) : 0;
            if (n) { host_mando_salida(luz, n); preparada = true; color = v; }
        }
    }
}

// El botón Mic sirve de modificador en la placa (p. ej. Mic + cruceta = fuerza del anti-recoil). A la PS5 solo
// le llega si se toca solo (pulsar y soltar sin tocar otro botón): entonces, al soltarlo, una pulsación corta.
static bool mic_para_la_ps5(const motor_estado_t *entrada, int64_t t)
{
    static bool abajo, usado;
    static uint32_t al_pulsar;
    static int64_t hasta;
    const uint32_t mic = 1u << MB_SILENCIAR;
    if (entrada->botones & mic) {
        if (!abajo) { abajo = true; usado = false; al_pulsar = entrada->botones & ~mic; }
        else if ((entrada->botones & ~mic & ~al_pulsar) != 0) usado = true;
    } else if (abajo) {
        abajo = false;
        if (!usado) hasta = t + 100000;
    }
    return t < hasta;
}

// Modo dualsense: la PS5 solo ve la placa cuando el DualSense real está montado en el MAX3421E. Así todo el
// saludo (informes de configuración y autenticación) le llega al mando de verdad desde el principio, y si el
// mando se desconecta, la PS5 ve desconectarse la placa y al volver lo repite todo. Si en unos segundos no
// hay mando, se conecta igual (para usarla con lo que mande el Mac).
static void conexion_con_la_ps5(int64_t t)
{
    static enum { ESPERANDO, CON_MANDO, SIN_MANDO, DESCONECTADA } estado = ESPERANDO;
    static int64_t desde, sin_mando;
    bool listo = host_mando_listo();
    switch (estado) {
    case ESPERANDO:
    case DESCONECTADA:
        if (listo && t - desde > 300000) {
            tud_connect();
            estado = CON_MANDO;
            sin_mando = 0;
            ESP_LOGI(TAG, "DualSense listo: la PS5 ya ve la placa");
        } else if (!listo && t - desde > 5000000) {
            tud_connect();
            estado = SIN_MANDO;
            ESP_LOGW(TAG, "Sin DualSense en el MAX3421E: la PS5 ve la placa sin mando real (no pasará la autenticación)");
        }
        break;
    case CON_MANDO:
        if (listo) { sin_mando = 0; break; }
        if (!sin_mando) sin_mando = t;
        if (t - sin_mando > 100000) {
            tud_disconnect();
            estado = DESCONECTADA;
            desde = t;
            ESP_LOGW(TAG, "El DualSense se ha desconectado: la placa se desconecta de la PS5 hasta que vuelva");
        }
        break;
    case SIN_MANDO:
        if (listo) {
            tud_disconnect();
            estado = DESCONECTADA;
            desde = t;
            ESP_LOGI(TAG, "Ha llegado el DualSense: reconecto con la PS5 para que lo salude de nuevo");
        }
        break;
    }
}

// Diagnóstico del relé: pasar el informe real sin la salida del motor, y los últimos informes para compararlos
// La PS5 comprueba los informes del DualSense: si cambia un solo valor de sticks o botones (aunque sea 1
// punto), descarta el informe; un byte de relleno sí se puede tocar (probado el 1-nov-2026). Por eso en modo
// dualsense el informe pasa tal cual (1) y el motor no puede actuar: para anti-recoil, ayuda, etc. hace
// falta el modo consola con el P5Mate. Los otros valores quedan para pruebas (orden serie «directo N»).
static volatile int directo = 1;   // 0 con el motor encima, 1 directo, 2 directo con el stick derecho en 0x80, 3 directo con un byte de relleno cambiado, 4 directo con el stick derecho X un punto menos
static uint8_t diag_real[64], diag_enviado[64];
static uint16_t largo_ultimo;
void usb_directo(int modo) { directo = modo; }

// Captura de lo que sale hacia la PS5 (y cómo venía del mando), informe a informe, para analizarlo
typedef struct { uint32_t us; uint8_t real[9]; uint8_t env[9]; } muestra_t;   // bytes 1..9: sticks, gatillos, seq, botones
static muestra_t *captura;
static volatile int captura_n, captura_max;
void usb_capturar(int n)
{
    if (!captura) captura = heap_caps_malloc(4000 * sizeof(muestra_t), MALLOC_CAP_SPIRAM);
    if (!captura) { responder("Sin memoria para la captura"); return; }
    captura_max = 0;
    captura_n = 0;
    captura_max = n > 4000 ? 4000 : n;
    responder("Capturando %d informes", captura_max);
}
void usb_volcar_captura(void)
{
    int n = captura_n;
    responder("@CAP %d", n);
    for (int i = 0; i < n; i++) {
        const muestra_t *m = &captura[i];
        responder("@C %lu %02x%02x%02x%02x%02x%02x%02x%02x%02x %02x%02x%02x%02x%02x%02x%02x%02x%02x", (unsigned long)m->us,
                  m->real[0], m->real[1], m->real[2], m->real[3], m->real[4], m->real[5], m->real[6], m->real[7], m->real[8],
                  m->env[0], m->env[1], m->env[2], m->env[3], m->env[4], m->env[5], m->env[6], m->env[7], m->env[8]);
        if (i % 50 == 49) vTaskDelay(1);
    }
    responder("@FIN");
}
void usb_volcar_informes(void)
{
    char hex[200];
    for (int fila = 0; fila < 2; fila++) {
        const uint8_t *b = fila ? diag_enviado : diag_real;
        for (int parte = 0; parte < 64; parte += 32) {
            int k = 0;
            for (int i = parte; i < parte + 32 && i < largo_ultimo; i++) k += sprintf(hex + k, "%02x ", b[i]);
            hex[k] = 0;
            responder("%s %2d: %s", fila ? "a la PS5" : "del mando", parte, hex);
        }
    }
}

static void tarea_informes(void *arg)
{
    uint8_t informe[64], real[64];
    uint16_t largo_real = 0;
    uint8_t contador = 0;
    uint16_t tiempo = 0;
    motor_estado_t entrada = { 0 };
    bool hay_entrada = false;
    int32_t bateria = -1;
    uint8_t estado_bateria = 3;
    int informes_seg = 0, envios_seg = 0;
    int64_t ultimo_real = 0, hueco_max = 0, contado = esp_timer_get_time();
    bool por_enviar = false;                 // informe real que aún no ha salido hacia la PS5
    while (true) {
        vTaskDelay(1);   // 1 ms (CONFIG_FREERTOS_HZ=1000)
        int64_t t = esp_timer_get_time();
        if (modo_usb == MODO_DUALSENSE) conexion_con_la_ps5(t);

        // 1. Lo que llega del DualSense real (en modo mac manda el Mac, que ya aplica el perfil)
        bool con_mando = modo_usb != MODO_MAC && host_mando_listo();
        if (!con_mando) {
            if (hay_entrada) luz_del_mando(t, true);
            hay_entrada = false;
        } else {
            uint16_t n;
            if (host_mando_informe(real, &n) && n > 1) {
                largo_real = n;
                por_enviar = true;
                informes_seg++;
                if (ultimo_real && t - ultimo_real > hueco_max) hueco_max = t - ultimo_real;
                ultimo_real = t;
                hay_entrada = motor_leer_dualsense(real, n, &entrada, &bateria, &estado_bateria);
            }
        }

        // 2. El motor: perfil, anti-recoil, ayuda al apuntado, turbo, macros, atajos del mando...
        motor_estado_t salida = motor_vuelta(hay_entrada ? &entrada : NULL, t);
        if (hay_entrada) luz_del_mando(t, false);
        if (t - contado >= 1000000) {        // una vez por segundo, el ritmo del mando para «En vivo»
            motor_poner_mando(con_mando, informes_seg, hueco_max / 1000.0f, bateria, estado_bateria, envios_seg);
            static int cada;
            if (modo_usb == MODO_DUALSENSE && con_mando && ++cada >= 5) {   // cada 5 s, el ritmo del relé
                cada = 0;
                uint32_t c[5];
                host_mando_contadores(c);
                ESP_LOGI(TAG, "ritmo: mando %d/s (hueco %lld ms) -> PS5 %d/s | salidas PS5 %lu en 5 s: juntadas %lu, al mando %lu, perdidas %lu",
                         informes_seg, hueco_max / 1000, envios_seg, (unsigned long)c[1], (unsigned long)c[2],
                         (unsigned long)c[3], (unsigned long)c[4]);
            }
            informes_seg = envios_seg = 0;
            hueco_max = 0;
            contado = t;
        }

        // 3. A la consola
        bool mic = hay_entrada && mic_para_la_ps5(&entrada, t);
        if (!tud_mounted() || !tud_hid_ready()) continue;
        if (modo_usb == MODO_DUALSENSE && con_mando) {
            // A la PS5, el informe real con la salida del motor encima, cada vez que llega uno nuevo (si en
            // ese momento el USB estaba ocupado, sale en la vuelta siguiente)
            if (por_enviar && hay_entrada) {
                memcpy(informe, real, largo_real);
                salida.botones = (salida.botones & ~(1u << MB_SILENCIAR)) | (mic ? 1u << MB_SILENCIAR : 0);
                if (directo == 0) motor_sobre_dualsense(informe, &salida);
                if (directo == 2) { informe[3] = 0x80; informe[4] = 0x80; }
                if (directo == 3 && largo_real > 46) informe[46] ^= 0x01;   // un byte de relleno (siempre 0)
                if (directo == 4) {                                          // stick derecho X un punto, sin pasar por 0x80
                    uint8_t x = informe[3] ? informe[3] - 1 : 1;
                    informe[3] = x == 0x80 ? 0x7E : x;
                }
                memcpy(diag_real, real, largo_real);
                memcpy(diag_enviado, informe, largo_real);
                largo_ultimo = largo_real;
                if (tud_hid_report(informe[0], informe + 1, largo_real - 1)) {
                    por_enviar = false;
                    envios_seg++;
                    if (captura && captura_n < captura_max) {
                        muestra_t *m = &captura[captura_n];
                        m->us = (uint32_t)t;
                        memcpy(m->real, real + 1, 9);
                        memcpy(m->env, informe + 1, 9);
                        captura_n++;
                    }
                }
            }
            continue;
        }
        mando_t m;
        if (con_mando && hay_entrada) motor_a_mando(&salida, &m);   // el mando real, ya procesado
        else mando_copiar(&m);                                       // lo que manda el Mac o las órdenes
        if (modo_usb == MODO_DUALSENSE) {
            construir_informe_dualsense(informe, &m, contador);
        } else {
            tiempo += 188;   // el DS4 cuenta en pasos de 5,33 µs: 1 ms son ~188
            construir_informe(informe, &m, contador, tiempo);
        }
        contador = (contador + 1) & 0x3F;
        tud_hid_report(0x01, informe + 1, 63);
        envios_seg++;
    }
}

// --- Puerto serie USB (solo en modo Mac) ---

static void al_recibir(int itf, cdcacm_event_t *evento)
{
    uint8_t datos[64];
    size_t leidos = 0;
    if (tinyusb_cdcacm_read(itf, datos, sizeof(datos), &leidos) == ESP_OK && leidos) {
        ordenes_bytes(datos, leidos, 1);
    }
}

void usb_serie_escribir(const char *texto, size_t largo)
{
    if (!hay_serie || !tud_cdc_n_connected(0)) return;
    tinyusb_cdcacm_write_queue(TINYUSB_CDC_ACM_0, (const uint8_t *)texto, largo);
    tinyusb_cdcacm_write_flush(TINYUSB_CDC_ACM_0, pdMS_TO_TICKS(20));
}

bool usb_conectado(void)     { return tud_mounted(); }
uint32_t usb_peticiones(void) { return peticiones; }

void usb_estado(void)
{
    responder("USB: %s, %lu peticiones de configuración",
              tud_mounted() ? "conectado" : "sin conectar", (unsigned long)peticiones);
    for (int id = 0; id < 256; id++) {
        if (veces_por_id[id]) responder("  informe 0x%02X: %lu veces", id, (unsigned long)veces_por_id[id]);
    }
}

void usb_ps4_iniciar(modo_t modo)
{
    modo_usb = modo;
    bool con_serie = (modo == MODO_MAC);
    hay_serie = con_serie;

    if (modo == MODO_DUALSENSE) {
        // Disfraz de DualSense (PS5): VID/PID y versión del mando real
        descriptor_dispositivo.idVendor = 0x054C;
        descriptor_dispositivo.idProduct = 0x0CE6;
        descriptor_dispositivo.bcdDevice = 0x0100;
    } else if (con_serie) {
        // Mando + puerto serie en el mismo cable: dispositivo compuesto
        descriptor_dispositivo.bDeviceClass = TUSB_CLASS_MISC;
        descriptor_dispositivo.bDeviceSubClass = MISC_SUBCLASS_COMMON;
        descriptor_dispositivo.bDeviceProtocol = MISC_PROTOCOL_IAD;
    }

    const uint8_t *config = modo == MODO_DUALSENSE ? config_dualsense
                          : con_serie              ? config_con_serie
                                                   : config_solo_mando;
    const char **strs = modo == MODO_DUALSENSE ? textos_ds : textos;
    int nstrs = modo == MODO_DUALSENSE ? (int)(sizeof(textos_ds) / sizeof(textos_ds[0]))
                                       : (int)(sizeof(textos) / sizeof(textos[0]));
    const tinyusb_config_t cfg = {
        .device_descriptor = &descriptor_dispositivo,
        .string_descriptor = strs,
        .string_descriptor_count = nstrs,
        .external_phy = false,
        .configuration_descriptor = config,
    };
    ESP_ERROR_CHECK(tinyusb_driver_install(&cfg));
    if (modo == MODO_DUALSENSE) tud_disconnect();   // hasta que esté el mando real (conexion_con_la_ps5)

    if (con_serie) {
        const tinyusb_config_cdcacm_t acm = {
            .usb_dev = TINYUSB_USBDEV_0,
            .cdc_port = TINYUSB_CDC_ACM_0,
            .callback_rx = al_recibir,
        };
        ESP_ERROR_CHECK(tusb_cdc_acm_init(&acm));
    }
    xTaskCreatePinnedToCore(tarea_informes, "informes", 16384, NULL, 10, NULL, 1);   // núcleo 1: la WiFi va en el 0
    ESP_LOGI(TAG, "USB listo en modo %s", modo == MODO_DUALSENSE ? "DualSense (PS5)"
             : con_serie ? "PS4 + serie (Mac)" : "PS4 (consola)");
}
