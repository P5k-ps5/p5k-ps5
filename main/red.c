// La WiFi de la placa, con «onboarding»: se conecta a la red de casa y, si no puede (no hay ninguna
// configurada, o ha cambiado la contraseña del router), abre su propia red para poder configurarla.
//
// - Red propia (AP): «p5k-ps5 XXXX», abierta o con contraseña (se cambia desde la página).
//   Mientras está abierta hay portal cautivo: la placa contesta a todas las consultas DNS con su
//   dirección (192.168.4.1), así el móvil abre la página solo al conectarse.
// - Red de casa (STA): la placa se anuncia como http://puente.local (mDNS) y pone la hora por NTP.
// Lo configurado va en la NVS (espacio «red»). Más detalles en PLACA-WEB.md.
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "esp_netif_sntp.h"
#include "esp_mac.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "nvs.h"
#include "mdns.h"
#include "lwip/sockets.h"
#include "cJSON.h"
#include "puente.h"

static const char *TAG = "red";

#define ESPERA_STA_US      (20 * 1000000LL)   // sin red de casa en 20 s: se abre la red propia
#define REINTENTO_STA_US   (60 * 1000000LL)   // con la red propia abierta y vacía, se reintenta la de casa cada minuto
#define REINTENTO_OCUPADA_US (180 * 1000000LL) // con móviles en la red propia, cada 3 min (un móvil puede quedarse en ella para siempre)
#define GRACIA_AP_US       (30 * 1000000LL)   // ya en casa: la red propia se cierra 30 s después de quedarse vacía
#define MAX_REDES 20
#define MAX_ACEPTADOS 8

static esp_netif_t *netif_sta, *netif_ap;
static SemaphoreHandle_t cerrojo;

// Lo guardado
static char sta_ssid[33], sta_clave[65];
static char ap_ssid[33], ap_clave[65];
static bool ap_siempre;

// El estado
static bool sta_conectada, ap_activa, buscando, intentando;
static volatile bool pendiente;          // la página pidió conectar a una red: lo hace tarea_red
static volatile bool desconectando;      // el próximo «desconectado» lo hemos pedido nosotros
static int ultimo_motivo;                // por qué falló el último intento (wifi_err_reason_t)
static esp_ip4_addr_t sta_ip;
static int sta_rssi;
static int64_t sin_sta_desde, ultimo_intento, ap_vacia_desde;
static wifi_ap_record_t redes[MAX_REDES];
static int num_redes;
static uint32_t aceptados[MAX_ACEPTADOS];   // móviles que ya han pasado el portal cautivo
static int num_aceptados;
static bool sntp_iniciado;

static int64_t ahora(void) { return esp_timer_get_time(); }

// --- Lo guardado en la NVS ---

static void leer_texto(nvs_handle_t h, const char *clave, char *dest, size_t cabe)
{
    size_t largo = cabe;
    if (nvs_get_str(h, clave, dest, &largo) != ESP_OK) dest[0] = 0;
}

static void cargar(void)
{
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
    snprintf(ap_ssid, sizeof(ap_ssid), "p5k-ps5 %02X%02X", mac[4], mac[5]);
    ap_clave[0] = 0;
    sta_ssid[0] = sta_clave[0] = 0;
    ap_siempre = false;
    nvs_handle_t h;
    if (nvs_open("red", NVS_READONLY, &h) == ESP_OK) {
        leer_texto(h, "sta_ssid", sta_ssid, sizeof(sta_ssid));
        leer_texto(h, "sta_clave", sta_clave, sizeof(sta_clave));
        char guardado[33];
        leer_texto(h, "ap_ssid", guardado, sizeof(guardado));
        if (guardado[0]) strcpy(ap_ssid, guardado);
        leer_texto(h, "ap_clave", ap_clave, sizeof(ap_clave));
        uint8_t s = 0;
        nvs_get_u8(h, "ap_siempre", &s);
        ap_siempre = s;
        nvs_close(h);
    }
}

static void guardar(void)
{
    nvs_handle_t h;
    if (nvs_open("red", NVS_READWRITE, &h) != ESP_OK) return;
    nvs_set_str(h, "sta_ssid", sta_ssid);
    nvs_set_str(h, "sta_clave", sta_clave);
    nvs_set_str(h, "ap_ssid", ap_ssid);
    nvs_set_str(h, "ap_clave", ap_clave);
    nvs_set_u8(h, "ap_siempre", ap_siempre);
    nvs_commit(h);
    nvs_close(h);
}

// --- Red propia (AP) y red de casa (STA) ---

static void configurar_ap(void)
{
    wifi_config_t c = { 0 };
    strncpy((char *)c.ap.ssid, ap_ssid, sizeof(c.ap.ssid));
    c.ap.ssid_len = strlen(ap_ssid);
    strncpy((char *)c.ap.password, ap_clave, sizeof(c.ap.password));
    c.ap.authmode = ap_clave[0] ? WIFI_AUTH_WPA2_PSK : WIFI_AUTH_OPEN;
    c.ap.max_connection = 4;
    c.ap.channel = 1;
    // En APSTA la red propia se mueve al canal de la de casa: si ya se sabe cuál es, se abre directamente en él
    for (int i = 0; i < num_redes; i++) {
        if (sta_ssid[0] && !strcmp((char *)redes[i].ssid, sta_ssid)) { c.ap.channel = redes[i].primary; break; }
    }
    c.ap.csa_count = 3;                                      // avisar a los móviles antes de cambiar de canal
    c.ap.pmf_cfg.required = false;
    esp_wifi_set_config(WIFI_IF_AP, &c);
}

static esp_err_t configurar_sta(void)
{
    wifi_config_t c = { 0 };
    strncpy((char *)c.sta.ssid, sta_ssid, sizeof(c.sta.ssid));
    strncpy((char *)c.sta.password, sta_clave, sizeof(c.sta.password));
    c.sta.threshold.authmode = sta_clave[0] ? WIFI_AUTH_WEP : WIFI_AUTH_OPEN;
    c.sta.scan_method = WIFI_ALL_CHANNEL_SCAN;
    c.sta.sort_method = WIFI_CONNECT_AP_BY_SIGNAL;
    c.sta.sae_pwe_h2e = WPA3_SAE_PWE_BOTH;                  // routers WPA3 que exigen H2E
    return esp_wifi_set_config(WIFI_IF_STA, &c);
}

static void abrir_ap(void)
{
    if (ap_activa) return;
    esp_wifi_set_mode(WIFI_MODE_APSTA);
    configurar_ap();
    ap_activa = true;
    ap_vacia_desde = ahora();
    ESP_LOGI(TAG, "Red propia abierta: «%s» (%s)", ap_ssid, ap_clave[0] ? "con contraseña" : "abierta");
}

static void cerrar_ap(void)
{
    if (!ap_activa) return;
    esp_wifi_set_mode(WIFI_MODE_STA);
    ap_activa = false;
    num_aceptados = 0;
    ESP_LOGI(TAG, "Red propia cerrada (ya está en la red de casa)");
}

static void intentar_sta(void)
{
    if (!sta_ssid[0] || buscando) return;
    if (configurar_sta() != ESP_OK) return;                  // aún conectando: se reintenta en la próxima vuelta
    intentando = true;
    ultimo_motivo = 0;
    ultimo_intento = ahora();
    esp_wifi_connect();
    ESP_LOGI(TAG, "Conectando a la red de casa «%s»...", sta_ssid);
}

static int clientes_ap(void)
{
    if (!ap_activa) return 0;
    wifi_sta_list_t lista;
    return esp_wifi_ap_get_sta_list(&lista) == ESP_OK ? lista.num : 0;
}

// --- Eventos ---

static int comparar_redes(const void *a, const void *b)
{
    return ((const wifi_ap_record_t *)b)->rssi - ((const wifi_ap_record_t *)a)->rssi;
}

static void al_terminar_busqueda(void)
{
    uint16_t n = 0;
    esp_wifi_scan_get_ap_num(&n);
    wifi_ap_record_t *todas = calloc(n ? n : 1, sizeof(wifi_ap_record_t));
    if (todas && esp_wifi_scan_get_ap_records(&n, todas) == ESP_OK) {
        qsort(todas, n, sizeof(wifi_ap_record_t), comparar_redes);
        xSemaphoreTake(cerrojo, portMAX_DELAY);
        num_redes = 0;
        for (int i = 0; i < n && num_redes < MAX_REDES; i++) {
            if (!todas[i].ssid[0]) continue;   // ocultas
            bool repetida = false;
            for (int j = 0; j < num_redes; j++) {
                if (!strcmp((char *)redes[j].ssid, (char *)todas[i].ssid)) { repetida = true; break; }
            }
            if (!repetida) redes[num_redes++] = todas[i];
        }
        xSemaphoreGive(cerrojo);
    } else {
        esp_wifi_clear_ap_list();
    }
    free(todas);
    buscando = false;
    ESP_LOGI(TAG, "Búsqueda terminada: %d redes", num_redes);
}

static void al_evento(void *arg, esp_event_base_t base, int32_t id, void *datos)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        wifi_event_sta_disconnected_t *d = datos;
        if (desconectando) {                                 // lo pedimos nosotros (cambio de red, búsqueda)
            desconectando = false;
            sta_conectada = false;
            intentando = false;
            return;
        }
        ultimo_motivo = d->reason;
        if (sta_conectada) {
            ESP_LOGW(TAG, "Se ha perdido la red de casa (motivo %d)", d->reason);
            sin_sta_desde = ahora();
        } else if (intentando) {
            ESP_LOGW(TAG, "No se pudo conectar a «%s» (motivo %d)", sta_ssid, d->reason);
        }
        sta_conectada = false;
        intentando = false;
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_SCAN_DONE) {
        al_terminar_busqueda();
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *e = datos;
        sta_ip = e->ip_info.ip;
        sta_conectada = true;
        intentando = false;
        ap_vacia_desde = ahora();
        ESP_LOGI(TAG, "En la red de casa «%s»: http://" IPSTR " y http://puente.local", sta_ssid, IP2STR(&sta_ip));
        if (!sntp_iniciado) {
            esp_sntp_config_t c = ESP_NETIF_SNTP_DEFAULT_CONFIG("pool.ntp.org");
            esp_netif_sntp_init(&c);
            sntp_iniciado = true;
        }
    }
}

// --- Portal cautivo: DNS que contesta todo con la dirección de la placa ---

static void tarea_dns(void *arg)
{
    int s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    struct sockaddr_in dir = { .sin_family = AF_INET, .sin_port = htons(53), .sin_addr.s_addr = htonl(INADDR_ANY) };
    if (s < 0 || bind(s, (struct sockaddr *)&dir, sizeof(dir)) < 0) {
        ESP_LOGE(TAG, "No se pudo abrir el DNS del portal");
        vTaskDelete(NULL);
        return;
    }
    uint8_t buf[512];
    while (true) {
        struct sockaddr_in de;
        socklen_t largo_de = sizeof(de);
        int n = recvfrom(s, buf, sizeof(buf) - 16, 0, (struct sockaddr *)&de, &largo_de);
        if (n < 12 || !ap_activa) continue;
        // Solo a quien está en la red propia
        esp_netif_ip_info_t ap;
        esp_netif_get_ip_info(netif_ap, &ap);
        if ((de.sin_addr.s_addr & ap.netmask.addr) != (ap.ip.addr & ap.netmask.addr)) continue;
        if (buf[2] & 0x80) continue;                         // es una respuesta, no una pregunta
        int qd = (buf[4] << 8) | buf[5];
        if (qd != 1) continue;
        // Fin de la pregunta: nombre (etiquetas) + tipo (2) + clase (2)
        int p = 12;
        while (p < n && buf[p]) p += buf[p] + 1;
        p += 5;
        if (p > n) continue;
        int tipo = (buf[p - 4] << 8) | buf[p - 3];
        buf[2] = 0x81; buf[3] = 0x80;                        // respuesta, recursión disponible, sin error
        buf[6] = 0; buf[7] = (tipo == 1) ? 1 : 0;            // una respuesta si preguntan por IPv4
        buf[8] = buf[9] = buf[10] = buf[11] = 0;
        int r = p;
        if (tipo == 1) {
            const uint8_t resp[] = { 0xC0, 0x0C, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4 };
            memcpy(buf + r, resp, sizeof(resp));
            r += sizeof(resp);
            memcpy(buf + r, &ap.ip.addr, 4);
            r += 4;
        }
        sendto(s, buf, r, 0, (struct sockaddr *)&de, largo_de);
    }
}

// --- La tarea que decide cuándo abrir y cerrar la red propia ---

static void tarea_red(void *arg)
{
    while (true) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        int64_t t = ahora();
        int clientes = clientes_ap();
        if (clientes > 0) ap_vacia_desde = t;

        // La página ha pedido conectar a una red: aunque haya móviles en la red propia (el que la pide está ahí)
        if (pendiente && !buscando) {
            if (sta_conectada || intentando) {
                desconectando = true;
                esp_wifi_disconnect();
                sta_conectada = intentando = false;
                vTaskDelay(pdMS_TO_TICKS(300));              // que llegue el «desconectado» antes de cambiar la config
            }
            if (configurar_sta() == ESP_OK) {
                pendiente = false;
                sin_sta_desde = t;
                intentar_sta();
            }
            continue;
        }

        if (!sta_ssid[0]) {
            abrir_ap();                                      // nada configurado: solo la red propia
            continue;
        }
        if (sta_conectada) {
            // Ya en casa: la red propia se cierra cuando lleva un rato vacía (así quien la configuró desde
            // ella ve el resultado antes de que se cierre), salvo que esté marcada «siempre encendida»
            if (ap_activa && !ap_siempre && t - ap_vacia_desde > GRACIA_AP_US) cerrar_ap();
            continue;
        }
        if (!ap_activa && t - sin_sta_desde > ESPERA_STA_US) abrir_ap();
        // Reintentos de la red de casa: seguidos si no hay red propia; con ella abierta, cada minuto y solo
        // si nadie está conectado (al buscar la red de casa la placa cambia de canal y molesta a los móviles)
        if (!intentando && !buscando) {
            if (!ap_activa && t - ultimo_intento > 5000000LL) intentar_sta();
            else if (ap_activa && clientes == 0 && t - ultimo_intento > REINTENTO_STA_US) intentar_sta();
            else if (ap_activa && clientes > 0 && t - ultimo_intento > REINTENTO_OCUPADA_US) intentar_sta();
        }
        if (intentando && t - ultimo_intento > 15000000LL) {
            desconectando = true;
            esp_wifi_disconnect();                           // este intento no ha salido
            intentando = false;
            if (!ultimo_motivo) ultimo_motivo = WIFI_REASON_CONNECTION_FAIL;
        }
    }
}

// --- Lo que usan el resto del firmware y la página ---

void red_iniciar(void)
{
    cerrojo = xSemaphoreCreateMutex();
    setenv("TZ", "CET-1CEST,M3.5.0,M10.5.0/3", 1);           // hora de España (península)
    tzset();
    cargar();

    ESP_ERROR_CHECK(esp_netif_init());
    esp_err_t e = esp_event_loop_create_default();
    if (e != ESP_OK && e != ESP_ERR_INVALID_STATE) ESP_ERROR_CHECK(e);
    netif_sta = esp_netif_create_default_wifi_sta();
    netif_ap = esp_netif_create_default_wifi_ap();
    esp_netif_set_hostname(netif_sta, "puente");

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));
    esp_wifi_set_storage(WIFI_STORAGE_RAM);                  // lo guardamos nosotros (espacio «red»)
    esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, al_evento, NULL);
    esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, al_evento, NULL);

    esp_wifi_set_mode(sta_ssid[0] ? WIFI_MODE_STA : WIFI_MODE_APSTA);
    if (!sta_ssid[0]) {
        configurar_ap();
        ap_activa = true;
    }
    ESP_ERROR_CHECK(esp_wifi_start());
    esp_wifi_set_ps(WIFI_PS_NONE);                           // sin ahorro de energía: menos retraso
    sin_sta_desde = ahora();
    if (ap_activa) ESP_LOGI(TAG, "Sin red de casa configurada: red propia «%s»", ap_ssid);
    if (ap_siempre) abrir_ap();
    intentar_sta();

    if (mdns_init() == ESP_OK) {
        mdns_hostname_set("puente");
        mdns_instance_name_set("p5k-ps5");
        mdns_service_add("p5k-ps5", "_http", "_tcp", 80, NULL, 0);
    }
    xTaskCreatePinnedToCore(tarea_red, "red", 4096, NULL, 3, NULL, 0);
    xTaskCreatePinnedToCore(tarea_dns, "dns", 3072, NULL, 3, NULL, 0);
}

bool red_por_ap(uint32_t ip)
{
    if (!ap_activa) return false;
    esp_netif_ip_info_t ap;
    esp_netif_get_ip_info(netif_ap, &ap);
    return (ip & ap.netmask.addr) == (ap.ip.addr & ap.netmask.addr);
}

bool red_ip_propia(const char *host)
{
    // ¿El «Host» de la petición es la placa? (si no, es un móvil comprobando si hay internet: portal)
    if (!host || !host[0]) return true;
    char ip[16];
    if (!strncmp(host, "puente.local", 12) || !strncmp(host, "puente", 6)) return true;
    esp_netif_ip_info_t info;
    esp_netif_get_ip_info(netif_ap, &info);
    snprintf(ip, sizeof(ip), IPSTR, IP2STR(&info.ip));
    if (!strncmp(host, ip, strlen(ip))) return true;
    if (sta_conectada) {
        snprintf(ip, sizeof(ip), IPSTR, IP2STR(&sta_ip));
        if (!strncmp(host, ip, strlen(ip))) return true;
    }
    return false;
}

void red_aceptar_portal(uint32_t ip)
{
    for (int i = 0; i < num_aceptados; i++) if (aceptados[i] == ip) return;
    if (num_aceptados < MAX_ACEPTADOS) aceptados[num_aceptados++] = ip;
    else aceptados[MAX_ACEPTADOS - 1] = ip;
}

bool red_portal_aceptado(uint32_t ip)
{
    for (int i = 0; i < num_aceptados; i++) if (aceptados[i] == ip) return true;
    return false;
}

void red_conectar(const char *ssid, const char *clave)
{
    strncpy(sta_ssid, ssid, sizeof(sta_ssid) - 1);
    sta_ssid[sizeof(sta_ssid) - 1] = 0;
    strncpy(sta_clave, clave ? clave : "", sizeof(sta_clave) - 1);
    sta_clave[sizeof(sta_clave) - 1] = 0;
    guardar();
    ultimo_motivo = 0;
    pendiente = true;                                        // lo hace tarea_red (desconectar, esperar, conectar)
}

void red_olvidar(void)
{
    sta_ssid[0] = sta_clave[0] = 0;
    guardar();
    pendiente = false;
    desconectando = true;
    esp_wifi_disconnect();
    sta_conectada = intentando = false;
    abrir_ap();
}

bool red_buscar(void)
{
    if (buscando) return true;
    if (intentando) {                                        // no se puede buscar mientras se conecta
        desconectando = true;
        esp_wifi_disconnect();
        intentando = false;
    }
    wifi_scan_config_t c = { .show_hidden = false };
    buscando = esp_wifi_scan_start(&c, false) == ESP_OK;
    return buscando;
}

static void aplicar_ap(void *arg)
{
    vTaskDelay(pdMS_TO_TICKS(2000));                         // que la respuesta llegue antes de cortar
    if (ap_activa) configurar_ap();
    else if (ap_siempre) abrir_ap();
    if (!ap_siempre && sta_conectada && clientes_ap() == 0) cerrar_ap();
    vTaskDelete(NULL);
}

const char *red_poner_ap(const char *ssid, const char *clave, bool siempre)
{
    size_t ls = ssid ? strlen(ssid) : 0, lc = clave ? strlen(clave) : 0;
    if (ls < 1 || ls > 32) return "El nombre de la red propia tiene que tener entre 1 y 32 caracteres";
    if (lc != 0 && (lc < 8 || lc > 63)) return "La contraseña tiene que tener entre 8 y 63 caracteres (o ninguna: red abierta)";
    strcpy(ap_ssid, ssid);
    strcpy(ap_clave, clave ? clave : "");
    ap_siempre = siempre;
    guardar();
    xTaskCreate(aplicar_ap, "aplicar_ap", 3072, NULL, 3, NULL);
    return NULL;
}

bool red_ap_abierta(void) { return ap_clave[0] == 0; }

// Rescate (BOOT 10 s u orden «wifi rescate»): la red propia, sin contraseña y abierta ya. Para cuando se ha
// olvidado su contraseña o la red de casa no deja entrar a la placa.
void red_rescate(void)
{
    ap_clave[0] = 0;
    guardar();
    if (ap_activa) configurar_ap();
    else abrir_ap();
    ap_vacia_desde = ahora() + 5 * 60 * 1000000LL;           // al menos 5 min abierta aunque esté en casa
    ESP_LOGW(TAG, "Rescate: red propia «%s» abierta y sin contraseña", ap_ssid);
}

static const char *texto_motivo(int m)
{
    switch (m) {
    case 0: return NULL;
    case WIFI_REASON_NO_AP_FOUND: return "No se encuentra esa red (¿está encendida y cerca? La placa solo ve redes de 2,4 GHz)";
    case WIFI_REASON_AUTH_FAIL: case WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT: case WIFI_REASON_HANDSHAKE_TIMEOUT:
    case WIFI_REASON_MIC_FAILURE: case WIFI_REASON_802_1X_AUTH_FAILED:
        return "La contraseña no es correcta";
    case WIFI_REASON_ASSOC_FAIL: case WIFI_REASON_AUTH_EXPIRE: case WIFI_REASON_CONNECTION_FAIL:
        return "El router no ha aceptado la conexión";
    default: return "No se pudo conectar";
    }
}

int red_direcciones(char dirs[][48], int max)
{
    int n = 0;
    if (sta_conectada && n < max) snprintf(dirs[n++], 48, "http://puente.local");
    if (sta_conectada && n < max) snprintf(dirs[n++], 48, "http://" IPSTR, IP2STR(&sta_ip));
    if (ap_activa && n < max) {
        esp_netif_ip_info_t info;
        esp_netif_get_ip_info(netif_ap, &info);
        snprintf(dirs[n++], 48, "http://" IPSTR, IP2STR(&info.ip));
    }
    return n;
}

void red_json(cJSON *r)
{
    if (sta_conectada) {
        wifi_ap_record_t info;
        if (esp_wifi_sta_get_ap_info(&info) == ESP_OK) sta_rssi = info.rssi;
    }
    char ip[16];
    cJSON *sta = cJSON_AddObjectToObject(r, "sta");
    cJSON_AddStringToObject(sta, "ssid", sta_ssid);
    cJSON_AddBoolToObject(sta, "configurada", sta_ssid[0] != 0);
    cJSON_AddBoolToObject(sta, "conectada", sta_conectada);
    snprintf(ip, sizeof(ip), IPSTR, IP2STR(&sta_ip));
    cJSON_AddStringToObject(sta, "ip", sta_conectada ? ip : "");
    if (sta_conectada) cJSON_AddNumberToObject(sta, "rssi", sta_rssi);
    else cJSON_AddNullToObject(sta, "rssi");
    cJSON_AddBoolToObject(sta, "conectando", pendiente || intentando);
    const char *motivo = sta_conectada ? NULL : texto_motivo(ultimo_motivo);
    if (motivo) cJSON_AddStringToObject(sta, "error", motivo); else cJSON_AddNullToObject(sta, "error");

    esp_netif_ip_info_t api;
    esp_netif_get_ip_info(netif_ap, &api);
    snprintf(ip, sizeof(ip), IPSTR, IP2STR(&api.ip));
    cJSON *ap = cJSON_AddObjectToObject(r, "ap");
    cJSON_AddStringToObject(ap, "ssid", ap_ssid);
    cJSON_AddBoolToObject(ap, "abierta", ap_clave[0] == 0);
    cJSON_AddBoolToObject(ap, "activa", ap_activa);
    cJSON_AddBoolToObject(ap, "siempre", ap_siempre);
    cJSON_AddStringToObject(ap, "ip", ip);
    cJSON_AddNumberToObject(ap, "clientes", clientes_ap());

    cJSON *lista = cJSON_AddArrayToObject(r, "redes");
    xSemaphoreTake(cerrojo, portMAX_DELAY);
    for (int i = 0; i < num_redes; i++) {
        cJSON *red = cJSON_CreateObject();
        cJSON_AddStringToObject(red, "ssid", (char *)redes[i].ssid);
        cJSON_AddNumberToObject(red, "rssi", redes[i].rssi);
        cJSON_AddBoolToObject(red, "segura", redes[i].authmode != WIFI_AUTH_OPEN);
        cJSON_AddItemToArray(lista, red);
    }
    xSemaphoreGive(cerrojo);
    cJSON_AddBoolToObject(r, "buscando", buscando);

    char dirs[3][48];
    int n = red_direcciones(dirs, 3);
    cJSON *d = cJSON_AddArrayToObject(r, "direcciones");
    for (int i = 0; i < n; i++) {
        if (ap_activa && !sta_conectada) break;              // la de la red propia no sirve desde casa
        if (strstr(dirs[i], ip)) continue;
        cJSON_AddItemToArray(d, cJSON_CreateString(dirs[i]));
    }
}

void red_estado(void)
{
    responder("WiFi: casa %s%s%s, red propia %s («%s», %s, %d conectados)",
              sta_ssid[0] ? "«" : "(sin configurar)", sta_ssid, sta_ssid[0] ? (sta_conectada ? "» conectada" : "» sin conexión") : "",
              ap_activa ? "abierta" : "cerrada", ap_ssid, ap_clave[0] ? "con contraseña" : "sin contraseña", clientes_ap());
    if (sta_conectada) responder("  En casa: http://" IPSTR "  y  http://puente.local", IP2STR(&sta_ip));
}

void red_listar(void)
{
    xSemaphoreTake(cerrojo, portMAX_DELAY);
    responder("Redes encontradas: %d%s", num_redes, buscando ? " (buscando...)" : "");
    for (int i = 0; i < num_redes; i++) {
        responder("  %-32s %4d dBm %s", (char *)redes[i].ssid, redes[i].rssi, redes[i].authmode == WIFI_AUTH_OPEN ? "abierta" : "");
    }
    xSemaphoreGive(cerrojo);
}
