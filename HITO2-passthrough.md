# Hito 2 — Passthrough con el mando real (MAX3421E)

Plan de software, listo para ejecutar en cuanto llegue el MAX3421E. Preparado sin gastar:
todo lo necesario ya está en el proyecto.

## Qué resuelve

En el Hito 1 (modo `dualsense`, ya en `main/`) probamos que **la PS5 acepta el disfraz de
DualSense** del ESP32 y arranca su diálogo. El muro: la PS5 hace un **desafío-respuesta
criptográfico** (reports `0x0A`/`0x80`/`0x81`, y luego `0xF0`/`0xF2`) que **solo el chip del mando
real sabe contestar**. El Hito 2 mete al mando real en el bucle para que conteste esos retos:

```
DualSense real ──USB──► MAX3421E (host, por SPI) ──► ESP32-S3 ──USB nativo (device)──► PS5
```

El ESP32 **reenvía** las peticiones de autenticación de la PS5 al mando real y devuelve sus
respuestas (relé transparente de los control transfers), y para el input lee el mando, aplica el
perfil (anti-recoil, etc.) y manda a la PS5 el informe **modificado**.

## Lo bueno: la base ya está

- TinyUSB 0.21.0 (en `managed_components/espressif__tinyusb`) **ya incluye el driver de host del
  MAX3421E** (`src/portable/analog/max3421/hcd_max3421.c`) y el stack de host (`usbh.c`, `hub.c`).
- TinyUSB corre **host + device a la vez**: device por el OTG nativo (lo que ya hace el modo
  dualsense) y host por el MAX3421E (SPI). Son controladores independientes.
- El OTG nativo del ESP32-S3 es de un solo rol (host **o** device), confirmado por Espressif — por
  eso el host va por el MAX3421E, no por el OTG.

## Conexiones (ESP32-S3 ↔ MAX3421E)

Solo se suelda la tira de pines al MAX3421E; el resto, cables dupont. GPIO elegidos libres en la
placa N16R8 (evitan USB 19/20, LED 48, BOOT 0, UART 43/44, PSRAM/flash 26-37, strapping 45/46):

| ESP32-S3 | MAX3421E | Qué es |
|---|---|---|
| 3V3 | VCC | alimentación (módulo de 3,3 V) |
| GND | GND | masa |
| GPIO12 | SCK | reloj SPI |
| GPIO11 | MOSI | datos ESP→MAX |
| GPIO13 | MISO | datos MAX→ESP |
| GPIO10 | SS (CS) | selección de chip |
| GPIO9 | INT | interrupción |
| 3V3 (o GPIO14) | RES | reset (puente a 3V3 vale) |

## Lo que hay que escribir

### 1. Glue de SPI (3 funciones que pide el HCD del MAX3421E)

Firmas confirmadas en `hcd_max3421.h`. Borrador para ESP-IDF (`main/max3421_glue.c`):

```c
#include "driver/spi_master.h"
#include "driver/gpio.h"
#include "tusb.h"

#define PIN_SCK 12
#define PIN_MOSI 11
#define PIN_MISO 13
#define PIN_CS  10
#define PIN_INT  9

static spi_device_handle_t spi;

static void IRAM_ATTR max3421_isr(void *arg) { tuh_int_handler(1, true); }  // rhport host = 1

void max3421_glue_init(void) {
    spi_bus_config_t bus = { .sclk_io_num = PIN_SCK, .mosi_io_num = PIN_MOSI,
        .miso_io_num = PIN_MISO, .quadwp_io_num = -1, .quadhd_io_num = -1, .max_transfer_sz = 128 };
    spi_bus_initialize(SPI2_HOST, &bus, SPI_DMA_CH_AUTO);
    spi_device_interface_config_t dev = { .clock_speed_hz = 26 * 1000 * 1000,  // MAX3421E hasta 26 MHz
        .mode = 0, .spics_io_num = -1, .queue_size = 1 };   // CS a mano (lo pide TinyUSB)
    spi_bus_add_device(SPI2_HOST, &dev, &spi);

    gpio_config_t cs = { .pin_bit_mask = 1ULL << PIN_CS, .mode = GPIO_MODE_OUTPUT };
    gpio_config(&cs); gpio_set_level(PIN_CS, 1);
    gpio_config_t in = { .pin_bit_mask = 1ULL << PIN_INT, .mode = GPIO_MODE_INPUT,
        .intr_type = GPIO_INTR_NEGEDGE, .pull_up_en = true };
    gpio_config(&in);
    gpio_install_isr_service(0);
    gpio_isr_handler_add(PIN_INT, max3421_isr, NULL);
}

void tuh_max3421_spi_cs_api(uint8_t rhport, bool active) {
    (void) rhport; gpio_set_level(PIN_CS, active ? 0 : 1);
}
bool tuh_max3421_spi_xfer_api(uint8_t rhport, uint8_t const *tx, uint8_t *rx, size_t len) {
    (void) rhport;
    spi_transaction_t t = { .length = len * 8, .tx_buffer = tx, .rx_buffer = rx };
    return spi_device_polling_transmit(spi, &t) == ESP_OK;
}
void tuh_max3421_int_api(uint8_t rhport, bool enabled) {
    (void) rhport;
    if (enabled) gpio_intr_enable(PIN_INT); else gpio_intr_disable(PIN_INT);
}
```

### 2. Activar el host en `tusb_config.h`

`esp_tinyusb` pasa su propio `tusb_config.h` (device-only) a TinyUSB
(`managed_components/espressif__esp_tinyusb/include/tusb_config.h`). Hay que añadir host. Opción
limpia: **vendorizar** `esp_tinyusb` (copiarlo a `components/` para que no lo pise una actualización)
y añadir a su `tusb_config.h`:

```c
#define CFG_TUH_ENABLED        1
#define CFG_TUH_MAX3421        1
#define CFG_TUH_RHPORT         1      // host en rhport 1 (device sigue en 0)
#define CFG_TUH_HUB            0
#define CFG_TUH_DEVICE_MAX     1
#define CFG_TUH_ENUMERATION_BUFSIZE 256
#define CFG_TUH_HID            2      // DualSense: interfaz de mando (y más si hiciera falta)
```

### 3. Tarea de host + enumeración del mando

Un `xTaskCreate` que llame a `max3421_glue_init()`, `tuh_init(1)` y en bucle `tuh_task()`.
Callbacks de TinyUSB host: `tuh_mount_cb` (mando conectado), `tuh_hid_mount_cb`/`tuh_hid_report_received_cb`
(informes de entrada del DualSense).

### 4. El relé de autenticación (el corazón del Hito 2)

Cuando la PS5 (lado device) hace un GET/SET de un report de auth (`0x0A`, `0x80`, `0x81`, `0xF0`,
`0xF1`, `0xF2`...), en vez de contestar con datos capturados, **reenviarlo al mando real** por un
control transfer del host (`tuh_control_xfer` con el `GET_REPORT`/`SET_REPORT` del HID) y devolver a
la PS5 lo que conteste el mando. Es un relé: no se entiende la cripto, solo se pasan los bytes.

- Reports de **setup estáticos** (`0x05`, `0x20`, `0x22`...) se pueden seguir sirviendo desde la
  captura (ya están) o reenviar también al mando (más fiel).
- Lo crítico es **la latencia**: la PS5 da un margen de tiempo para la auth. El relé software de la
  Raspberry (investigación `dualsense-ps5-usb-research`) falló justo aquí por timing. El ESP32 con
  SPI a 26 MHz debería ir más fino, pero **es la incógnita que valida o tumba todo el proyecto**.

### 5. Input con perfil

Leído el informe del mando real (`tuh_hid_report_received_cb`), convertirlo a `mando_t`, pasarlo por
el procesador del perfil (como hace hoy la app de escritorio) y mandar a la PS5 el informe DualSense
modificado (`construir_informe_dualsense`, ya está).

## Trampas conocidas

- **ESP32-S3 DP/DM a Serial-JTAG al arrancar**: hubo un bug (arreglado en ESP-IDF, abril 2025; vamos
  en 5.5.6, OK) por el que el USB fallaba enchufado directo. Si pasa, mirar ese fix.
- **FIFO/endpoints del OTG**: el device DualSense solo-HID cabe de sobra; el host va por el MAX3421E,
  aparte.
- **`esp_tinyusb` es solo-device**: el host se arranca con la API cruda de TinyUSB (`tuh_*`), no con
  el wrapper.
- **Orden de arranque**: device (OTG) y host (MAX3421E) se inician por separado; cuidado con que el
  `tusb_init`/`tud` del wrapper no pise la config del host.

## Referencias

- Driver y ejemplo en el propio repo: `managed_components/espressif__tinyusb/src/portable/analog/max3421/`
  y `hw/bsp/rp2040/boards/feather_rp2040_max3421/`.
- Investigación del protocolo: repos `dualsense-ps5-usb-research` (ShadowByteOS / 0xThreadz).
- Lectura de mandos por host con MAX3421E: ejemplos de Adafruit USB Host (MAX3421E).
