// El servidor web de la placa: la misma app web que sirven la app de Mac y la de escritorio (sacada de
// app/Pagina.swift al compilar), con las mismas rutas (/perfil, /estado, /eventos, /medidor, /movil,
// POST /api), más la pestaña Placa (/wifi, /firmware) y el portal cautivo de la red propia.
// Contrato completo en PLACA-WEB.md.
#include <string.h>
#include <stdlib.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "esp_http_server.h"
#include "esp_ota_ops.h"
#include "esp_app_desc.h"
#include "esp_timer.h"
#include "esp_system.h"
#include "esp_log.h"
#include "lwip/sockets.h"
#include "cJSON.h"
#include "motor.h"
#include "puente.h"

static const char *TAG = "web";

extern const uint8_t pagina_inicio[] asm("_binary_pagina_html_gz_start");
extern const uint8_t pagina_fin[] asm("_binary_pagina_html_gz_end");
extern const uint8_t icono_inicio[] asm("_binary_128x128_2x_png_start");
extern const uint8_t icono_fin[] asm("_binary_128x128_2x_png_end");

#define MAX_DIRECTOS 4                    // móviles mirando «En vivo» a la vez
#define MAX_CUERPO   (16 * 1024)          // POST /api y /wifi

static httpd_handle_t servidor;
static SemaphoreHandle_t cerrojo;
static httpd_req_t *directos[MAX_DIRECTOS];

// --- Ayudas ---

static uint32_t ip_cliente(httpd_req_t *req)
{
    int fd = httpd_req_to_sockfd(req);
    struct sockaddr_storage dir;
    socklen_t largo = sizeof(dir);
    if (getpeername(fd, (struct sockaddr *)&dir, &largo) != 0) return 0;
    if (dir.ss_family == AF_INET) return ((struct sockaddr_in *)&dir)->sin_addr.s_addr;
#if CONFIG_LWIP_IPV6
    if (dir.ss_family == AF_INET6) {
        const struct sockaddr_in6 *d6 = (const struct sockaddr_in6 *)&dir;
        if (d6->sin6_addr.un.u32_addr[0] == 0 && d6->sin6_addr.un.u32_addr[1] == 0 &&
            d6->sin6_addr.un.u32_addr[2] == htonl(0xFFFF)) return d6->sin6_addr.un.u32_addr[3];   // ::ffff:a.b.c.d
    }
#endif
    return 0;
}

static bool cabecera(httpd_req_t *req, const char *nombre, char *buf, size_t cabe)
{
    buf[0] = 0;
    return httpd_req_get_hdr_value_str(req, nombre, buf, cabe) == ESP_OK;
}

static void decodificar(char *s)
{
    char *o = s;
    for (char *p = s; *p; p++) {
        if (*p == '%' && p[1] && p[2]) {
            char h[3] = { p[1], p[2], 0 };
            *o++ = (char)strtol(h, NULL, 16);
            p += 2;
        } else if (*p == '+') {
            *o++ = ' ';
        } else {
            *o++ = *p;
        }
    }
    *o = 0;
}

static esp_err_t enviar(httpd_req_t *req, const char *estado, const char *tipo, const char *datos, ssize_t largo)
{
    httpd_resp_set_status(req, estado);
    httpd_resp_set_type(req, tipo);
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    return httpd_resp_send(req, datos, largo);
}

static esp_err_t enviar_json(httpd_req_t *req, const char *json)
{
    return enviar(req, "200 OK", "application/json; charset=utf-8", json ? json : "{}", HTTPD_RESP_USE_STRLEN);
}

static esp_err_t enviar_motor(httpd_req_t *req, char *json)
{
    esp_err_t e = enviar_json(req, json);
    motor_liberar(json);
    return e;
}

static esp_err_t redirigir(httpd_req_t *req, const char *a)
{
    httpd_resp_set_status(req, "302 Found");
    httpd_resp_set_hdr(req, "Location", a);
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    return httpd_resp_send(req, NULL, 0);
}

// La clave: como en el Mac (?k=), salvo por la red propia de la placa (quien está en ella ya ha pasado por
// su contraseña). Tras 8 fallos en un minuto se bloquea un minuto.
static int64_t fallos[8];
static int64_t bloqueado_hasta;

static bool autorizado(httpd_req_t *req)
{
    if (red_por_ap(ip_cliente(req))) return true;
    int64_t t = esp_timer_get_time();
    char consulta[160], k[64] = "";
    if (httpd_req_get_url_query_str(req, consulta, sizeof(consulta)) == ESP_OK) {
        httpd_query_key_value(consulta, "k", k, sizeof(k));
        decodificar(k);
    }
    char *clave = motor_clave();
    bool ok = clave && clave[0] && !strcmp(k, clave);
    motor_liberar(clave);
    if (ok) return true;                                     // la clave buena pasa aunque haya bloqueo
    if (t < bloqueado_hasta) {
        enviar(req, "429 Too Many Requests", "text/plain; charset=utf-8", "Demasiados intentos", HTTPD_RESP_USE_STRLEN);
        return false;
    }
    int recientes = 0;
    for (int i = 0; i < 8; i++) if (t - fallos[i] < 60000000LL) recientes++;
    for (int i = 7; i > 0; i--) fallos[i] = fallos[i - 1];
    fallos[0] = t;
    if (recientes + 1 >= 8) {
        bloqueado_hasta = t + 60000000LL;
        memset(fallos, 0, sizeof(fallos));
    }
    enviar(req, "401 Unauthorized", "text/plain; charset=utf-8", "Falta la clave", HTTPD_RESP_USE_STRLEN);
    return false;
}

// Los POST que cambian algo llevan además «X-Puente: 1» (otra web no puede mandarla sin permiso)
static bool permitido_post(httpd_req_t *req)
{
    char v[8];
    if (!cabecera(req, "X-Puente", v, sizeof(v)) || strcmp(v, "1")) {
        enviar(req, "400 Bad Request", "application/json; charset=utf-8", "{\"ok\":false,\"error\":\"petición no válida\"}", HTTPD_RESP_USE_STRLEN);
        return false;
    }
    return autorizado(req);
}

static char *leer_cuerpo(httpd_req_t *req)
{
    if (req->content_len > MAX_CUERPO) {
        enviar(req, "413 Payload Too Large", "text/plain; charset=utf-8", "Demasiado grande", HTTPD_RESP_USE_STRLEN);
        return NULL;
    }
    char *buf = malloc(req->content_len + 1);
    if (!buf) return NULL;
    size_t leido = 0;
    int esperas = 0;
    while (leido < req->content_len) {
        int n = httpd_req_recv(req, buf + leido, req->content_len - leido);
        if (n == HTTPD_SOCK_ERR_TIMEOUT && ++esperas < 3) continue;   // 3 × 10 s y se deja
        if (n <= 0) { free(buf); return NULL; }
        esperas = 0;
        leido += n;
    }
    buf[leido] = 0;
    return buf;
}

// Algo que hay que hacer después de contestar (reiniciar, cambiar de modo)
typedef enum { DESPUES_REINICIAR, DESPUES_CONSOLA = 10 + MODO_CONSOLA, DESPUES_MAC = 10 + MODO_MAC,
               DESPUES_DUALSENSE = 10 + MODO_DUALSENSE } despues_t;

static void tarea_despues(void *arg)
{
    vTaskDelay(pdMS_TO_TICKS(800));
    int que = (int)(intptr_t)arg;
    if (que >= 10) modo_poner((modo_t)(que - 10));
    else esp_restart();
    vTaskDelete(NULL);
}

static void despues(despues_t que)
{
    xTaskCreate(tarea_despues, "despues", 4096, (void *)(intptr_t)que, 5, NULL);
}

// --- La página ---

static esp_err_t servir_pagina(httpd_req_t *req)
{
    httpd_resp_set_type(req, "text/html; charset=utf-8");
    httpd_resp_set_hdr(req, "Content-Encoding", "gzip");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    return httpd_resp_send(req, (const char *)pagina_inicio, pagina_fin - pagina_inicio);
}

static esp_err_t ir_al_portal(httpd_req_t *req)
{
    return redirigir(req, "http://192.168.4.1/portal");
}

static esp_err_t h_raiz(httpd_req_t *req)
{
    char host[64];
    cabecera(req, "Host", host, sizeof(host));
    if (!red_ip_propia(host)) return ir_al_portal(req);      // un móvil probando si hay internet
    // Desde la red propia, la página entra con la clave ya puesta
    if (red_por_ap(ip_cliente(req))) {
        char *clave = motor_clave();
        char destino[96];
        snprintf(destino, sizeof(destino), "/p#k=%s", clave ? clave : "");
        motor_liberar(clave);
        return redirigir(req, destino);
    }
    return servir_pagina(req);
}

static esp_err_t h_pagina(httpd_req_t *req) { return servir_pagina(req); }

static esp_err_t h_icono(httpd_req_t *req)
{
    httpd_resp_set_type(req, "image/png");
    httpd_resp_set_hdr(req, "Cache-Control", "public, max-age=86400");
    return httpd_resp_send(req, (const char *)icono_inicio, icono_fin - icono_inicio);
}

// --- Portal cautivo ---

static const char PORTAL_CSS[] =
    "body{font:14px/1.42 -apple-system,system-ui,sans-serif;margin:0;padding:28px 16px;background:#000;color:#fff}"
    ".c{max-width:420px;margin:0 auto}img{width:56px;height:56px;display:block}"
    "h1{font-size:30px;line-height:1;font-weight:500;letter-spacing:-.03em;margin:16px 0 8px}p{color:rgba(255,255,255,.68);margin:8px 0}"
    ".dir{font:400 22px ui-monospace,Menlo,monospace;color:#c8f04d;border:1px solid rgba(255,255,255,.16);padding:12px;margin:14px 0;user-select:all;-webkit-user-select:all}"
    ".b{display:block;width:100%;box-sizing:border-box;padding:13px;border:1px solid rgba(255,255,255,.16);border-radius:0;font:500 15px -apple-system,system-ui,sans-serif;text-align:center;margin:8px 0;text-decoration:none;cursor:pointer}"
    ".p{background:#fff;border-color:#fff;color:#000;border-radius:999px}.s{background:rgba(255,255,255,.08);color:#fff}small{color:rgba(255,255,255,.46)}";

static esp_err_t h_portal(httpd_req_t *req)
{
    char *clave = motor_clave();
    char *html = malloc(3072);
    if (!html) { motor_liberar(clave); return ESP_FAIL; }
    snprintf(html, 3072,
        "<!doctype html><html lang=\"es\"><head><meta charset=\"utf-8\">"
        "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>p5k-ps5</title>"
        "<style>%s</style></head><body><div class=\"c\">"
        "<img src=\"/icono.png\" alt=\"\"><h1>p5k-ps5</h1>"
        "<p>Estás conectado a la red de la placa. Su dirección es:</p>"
        "<div class=\"dir\" id=\"d\">192.168.4.1</div>"
        "<a class=\"b p\" href=\"/p#k=%s\">Abrir la app aquí</a>"
        "<button class=\"b s\" id=\"c\">Copiar la dirección</button>"
        "<a class=\"b s\" href=\"/portal/ok\">Usarla en el navegador</a>"
        "<p><small>«Usarla en el navegador» deja el móvil conectado a esta red aunque no tenga internet. "
        "Después cierra esta ventana («Listo» en el iPhone) y escribe <b>192.168.4.1</b> en Safari o Chrome.</small></p>"
        "</div><script>"
        "var c=document.getElementById('c');c.onclick=function(){var t='http://192.168.4.1';"
        "function ok(){c.textContent='Dirección copiada'}"
        "if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(t).then(ok,function(){sel()})}else sel();"
        "function sel(){var r=document.createRange();r.selectNodeContents(document.getElementById('d'));"
        "var s=getSelection();s.removeAllRanges();s.addRange(r);try{document.execCommand('copy');ok()}catch(e){}}};"
        "</script></body></html>",
        PORTAL_CSS, clave ? clave : "");
    motor_liberar(clave);
    esp_err_t e = enviar(req, "200 OK", "text/html; charset=utf-8", html, HTTPD_RESP_USE_STRLEN);
    free(html);
    return e;
}

static esp_err_t h_portal_ok(httpd_req_t *req)
{
    red_aceptar_portal(ip_cliente(req));
    char *clave = motor_clave();
    char *html = malloc(2048);
    if (!html) { motor_liberar(clave); return ESP_FAIL; }
    snprintf(html, 2048,
        "<!doctype html><html lang=\"es\"><head><meta charset=\"utf-8\">"
        "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>p5k-ps5</title>"
        "<style>%s</style></head><body><div class=\"c\">"
        "<img src=\"/icono.png\" alt=\"\"><h1>¡Listo!</h1>"
        "<p>El móvil se queda conectado a la placa. Cierra esta ventana («Listo» en el iPhone) "
        "y abre en el navegador:</p><div class=\"dir\">192.168.4.1</div>"
        "<a class=\"b s\" href=\"/p#k=%s\">O abrir la app aquí</a></div></body></html>",
        PORTAL_CSS, clave ? clave : "");
    motor_liberar(clave);
    esp_err_t e = enviar(req, "200 OK", "text/html; charset=utf-8", html, HTTPD_RESP_USE_STRLEN);
    free(html);
    return e;
}

// Las comprobaciones de «¿hay internet?» de cada sistema: portal hasta que el móvil pasa por /portal/ok;
// después, la respuesta que espera cada uno (así no se cambia a los datos móviles ni insiste con el portal)
static esp_err_t h_sonda(httpd_req_t *req)
{
    if (!red_portal_aceptado(ip_cliente(req))) return ir_al_portal(req);
    const char *u = req->uri;
    if (strstr(u, "generate_204") || strstr(u, "gen_204")) {
        httpd_resp_set_status(req, "204 No Content");
        return httpd_resp_send(req, NULL, 0);
    }
    if (strstr(u, "connecttest")) return enviar(req, "200 OK", "text/plain", "Microsoft Connect Test", HTTPD_RESP_USE_STRLEN);
    if (strstr(u, "ncsi")) return enviar(req, "200 OK", "text/plain", "Microsoft NCSI", HTTPD_RESP_USE_STRLEN);
    if (strstr(u, "success.txt")) return enviar(req, "200 OK", "text/plain", "success\n", HTTPD_RESP_USE_STRLEN);
    return enviar(req, "200 OK", "text/html",
                  "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>", HTTPD_RESP_USE_STRLEN);
}

static esp_err_t h_resto(httpd_req_t *req)
{
    char host[64];
    cabecera(req, "Host", host, sizeof(host));
    if (!red_ip_propia(host)) return ir_al_portal(req);
    return enviar(req, "404 Not Found", "text/plain; charset=utf-8", "No existe", HTTPD_RESP_USE_STRLEN);
}

// --- Lo de siempre (mismo JSON que el escritorio) ---

static esp_err_t h_estado(httpd_req_t *req)
{
    if (!autorizado(req)) return ESP_OK;
    return enviar_motor(req, motor_instantanea());
}

static esp_err_t h_perfil(httpd_req_t *req)
{
    if (!autorizado(req)) return ESP_OK;
    return enviar_motor(req, motor_perfil());
}

static esp_err_t h_medidor(httpd_req_t *req)
{
    if (!autorizado(req)) return ESP_OK;
    return enviar_motor(req, motor_medidor());
}

static int contar_directos(void)
{
    int n = 0;
    xSemaphoreTake(cerrojo, portMAX_DELAY);
    for (int i = 0; i < MAX_DIRECTOS; i++) if (directos[i]) n++;
    xSemaphoreGive(cerrojo);
    return n;
}

static esp_err_t h_movil(httpd_req_t *req)
{
    if (!autorizado(req)) return ESP_OK;
    char dirs[3][48];
    int n = red_direcciones(dirs, 3);
    char *clave = motor_clave();
    cJSON *r = cJSON_CreateObject();
    cJSON *lista = cJSON_AddArrayToObject(r, "direcciones");
    char primera[112] = "";
    for (int i = 0; i < n; i++) {
        char con_clave[112];
        snprintf(con_clave, sizeof(con_clave), "%s/#k=%s", dirs[i], clave ? clave : "");
        if (!primera[0]) strcpy(primera, con_clave);
        cJSON_AddItemToArray(lista, cJSON_CreateString(con_clave));
    }
    motor_liberar(clave);
    char *qr = primera[0] ? motor_qr_svg(primera) : NULL;
    if (qr) cJSON_AddStringToObject(r, "qr", qr); else cJSON_AddNullToObject(r, "qr");
    motor_liberar(qr);
    cJSON_AddNumberToObject(r, "clientes", contar_directos());
    cJSON_AddNumberToObject(r, "puerto", 80);
    cJSON_AddBoolToObject(r, "activo", true);
    cJSON_AddBoolToObject(r, "local", false);
    char *json = cJSON_PrintUnformatted(r);
    cJSON_Delete(r);
    esp_err_t e = enviar_json(req, json);
    free(json);
    return e;
}

static esp_err_t h_api(httpd_req_t *req)
{
    if (!permitido_post(req)) return ESP_OK;
    char *cuerpo = leer_cuerpo(req);
    if (!cuerpo) return ESP_OK;
    char *r = motor_aplicar(cuerpo);
    free(cuerpo);
    return enviar_motor(req, r);
}

// «En vivo»: eventos del servidor (EventSource), 20 veces por segundo
static esp_err_t h_eventos(httpd_req_t *req)
{
    if (!autorizado(req)) return ESP_OK;
    if (contar_directos() >= MAX_DIRECTOS) {
        return enviar(req, "503 Service Unavailable", "text/plain; charset=utf-8", "Demasiados móviles mirando a la vez",
                      HTTPD_RESP_USE_STRLEN);
    }
    // Un móvil con mala señal no puede frenar a los demás: los envíos a este socket esperan como mucho 300 ms
    struct timeval espera = { .tv_sec = 0, .tv_usec = 300000 };
    setsockopt(httpd_req_to_sockfd(req), SOL_SOCKET, SO_SNDTIMEO, &espera, sizeof(espera));
    httpd_req_t *copia = NULL;
    if (httpd_req_async_handler_begin(req, &copia) != ESP_OK) return ESP_FAIL;
    httpd_resp_set_type(copia, "text/event-stream");
    httpd_resp_set_hdr(copia, "Cache-Control", "no-store");
    httpd_resp_set_hdr(copia, "X-Accel-Buffering", "no");
    char *inst = motor_instantanea();
    size_t largo = strlen(inst) + 9;
    char *msg = malloc(largo);
    bool ok = msg && snprintf(msg, largo, "data: %s\n\n", inst) > 0 && httpd_resp_send_chunk(copia, msg, strlen(msg)) == ESP_OK;
    free(msg);
    motor_liberar(inst);
    bool guardado = false;
    if (ok) {
        xSemaphoreTake(cerrojo, portMAX_DELAY);
        for (int i = 0; i < MAX_DIRECTOS && !guardado; i++) {
            if (!directos[i]) { directos[i] = copia; guardado = true; }
        }
        xSemaphoreGive(cerrojo);
    }
    if (!guardado) {
        if (ok) httpd_resp_send_chunk(copia, NULL, 0);      // cerrar la respuesta, que el navegador lo sepa
        httpd_req_async_handler_complete(copia);
    }
    return ESP_OK;
}

static void tarea_directo(void *arg)
{
    while (true) {
        vTaskDelay(pdMS_TO_TICKS(50));
        if (!contar_directos()) continue;
        char *inst = motor_instantanea();
        size_t largo = strlen(inst) + 9;
        char *msg = malloc(largo);
        if (msg) {
            snprintf(msg, largo, "data: %s\n\n", inst);
            // Se envía sin el cerrojo (cada envío puede tardar hasta 300 ms): esta tarea es la única que quita
            // directos de la lista, así que los que copia siguen vivos mientras envía
            httpd_req_t *lista[MAX_DIRECTOS];
            xSemaphoreTake(cerrojo, portMAX_DELAY);
            memcpy(lista, directos, sizeof(lista));
            xSemaphoreGive(cerrojo);
            for (int i = 0; i < MAX_DIRECTOS; i++) {
                if (lista[i] && httpd_resp_send_chunk(lista[i], msg, strlen(msg)) != ESP_OK) {
                    xSemaphoreTake(cerrojo, portMAX_DELAY);
                    directos[i] = NULL;
                    xSemaphoreGive(cerrojo);
                    httpd_req_async_handler_complete(lista[i]);   // el móvil se ha ido (o no da abasto)
                }
            }
            free(msg);
        }
        motor_liberar(inst);
    }
}

// --- Pestaña Placa: WiFi, modo, firmware ---

static esp_err_t h_wifi(httpd_req_t *req)
{
    if (!autorizado(req)) return ESP_OK;
    cJSON *r = cJSON_CreateObject();
    red_json(r);
    cJSON_AddBoolToObject(r, "porRedPropia", red_por_ap(ip_cliente(req)));
    cJSON_AddStringToObject(r, "modo", modo_nombre());
    cJSON_AddBoolToObject(r, "mandoReal", host_mando_listo());
    cJSON_AddStringToObject(r, "firmware", esp_app_get_description()->version);
    char *json = cJSON_PrintUnformatted(r);
    cJSON_Delete(r);
    esp_err_t e = enviar_json(req, json);
    free(json);
    return e;
}

static esp_err_t responder_resultado(httpd_req_t *req, const char *error, const char *info)
{
    cJSON *r = cJSON_CreateObject();
    cJSON_AddBoolToObject(r, "ok", error == NULL);
    if (error) cJSON_AddStringToObject(r, "error", error);
    if (info) cJSON_AddStringToObject(r, "info", info);
    char *json = cJSON_PrintUnformatted(r);
    cJSON_Delete(r);
    esp_err_t e = enviar_json(req, json);
    free(json);
    return e;
}

static const char *texto_de(cJSON *o, const char *k)
{
    cJSON *v = cJSON_GetObjectItemCaseSensitive(o, k);
    return cJSON_IsString(v) ? v->valuestring : NULL;
}

static esp_err_t h_wifi_post(httpd_req_t *req)
{
    if (!permitido_post(req)) return ESP_OK;
    char *cuerpo = leer_cuerpo(req);
    if (!cuerpo) return ESP_OK;
    cJSON *o = cJSON_Parse(cuerpo);
    free(cuerpo);
    const char *accion = o ? texto_de(o, "accion") : NULL;
    const char *error = NULL, *info = NULL;
    char frase[96];
    if (!accion) {
        error = "petición no válida";
    } else if (!strcmp(accion, "conectar")) {
        const char *ssid = texto_de(o, "ssid"), *clave = texto_de(o, "clave");
        if (!ssid || !ssid[0] || strlen(ssid) > 32) error = "Falta el nombre de la red";
        else if (clave && strlen(clave) > 63) error = "La contraseña es demasiado larga";
        else {
            red_conectar(ssid, clave ? clave : "");
            snprintf(frase, sizeof(frase), "Conectando a «%s»…", ssid);
            info = frase;
        }
    } else if (!strcmp(accion, "olvidar")) {
        red_olvidar();
        info = "Red de casa olvidada: la placa abre su red propia";
    } else if (!strcmp(accion, "buscar")) {
        if (!red_buscar()) error = "No se pudo buscar redes ahora; prueba otra vez en unos segundos";
    } else if (!strcmp(accion, "ap")) {
        cJSON *s = cJSON_GetObjectItemCaseSensitive(o, "siempre");
        error = red_poner_ap(texto_de(o, "ssid"), texto_de(o, "clave"), cJSON_IsTrue(s));
        if (!error) info = "Red propia guardada: se aplica en 2 segundos";
    } else if (!strcmp(accion, "modo")) {
        const char *m = texto_de(o, "modo");
        if (m && !strcmp(m, "consola")) despues(DESPUES_CONSOLA);
        else if (m && !strcmp(m, "mac")) despues(DESPUES_MAC);
        else if (m && !strcmp(m, "dualsense")) despues(DESPUES_DUALSENSE);
        else error = "Modo no válido";
        if (!error) info = "Cambiando de modo: la placa se reinicia";
    } else if (!strcmp(accion, "reiniciar")) {
        despues(DESPUES_REINICIAR);
        info = "Reiniciando la placa";
    } else {
        error = "acción desconocida";
    }
    cJSON_Delete(o);
    return responder_resultado(req, error, info);
}

static esp_err_t h_firmware(httpd_req_t *req)
{
    if (!permitido_post(req)) return ESP_OK;
    if (red_por_ap(ip_cliente(req)) && red_ap_abierta()) {
        return responder_resultado(req, "Por seguridad, desde la red propia de la placa sin contraseña no se puede "
                                        "actualizar el firmware: ponle contraseña o hazlo desde la wifi de casa", NULL);
    }
    const esp_partition_t *destino = esp_ota_get_next_update_partition(NULL);
    esp_ota_handle_t ota;
    if (!destino || esp_ota_begin(destino, OTA_WITH_SEQUENTIAL_WRITES, &ota) != ESP_OK) {
        return responder_resultado(req, "No se puede actualizar ahora", NULL);
    }
    ESP_LOGI(TAG, "Firmware nuevo (%d bytes) a la partición %s", req->content_len, destino->label);
    char *buf = malloc(4096);
    size_t queda = req->content_len;
    esp_err_t e = buf ? ESP_OK : ESP_ERR_NO_MEM;
    int esperas = 0;
    while (e == ESP_OK && queda > 0) {
        int n = httpd_req_recv(req, buf, queda < 4096 ? queda : 4096);
        if (n == HTTPD_SOCK_ERR_TIMEOUT && ++esperas < 3) continue;   // el móvil se ha ido: se deja
        if (n <= 0) { e = ESP_FAIL; break; }
        esperas = 0;
        e = esp_ota_write(ota, buf, n);
        queda -= n;
    }
    free(buf);
    if (e != ESP_OK) {
        esp_ota_abort(ota);
        return responder_resultado(req, "El archivo no se pudo grabar (¿es el .bin de la placa?)", NULL);
    }
    if (esp_ota_end(ota) != ESP_OK || esp_ota_set_boot_partition(destino) != ESP_OK) {
        return responder_resultado(req, "El archivo no es un firmware válido para la placa", NULL);
    }
    despues(DESPUES_REINICIAR);
    return responder_resultado(req, NULL, "Firmware actualizado: la placa se reinicia");
}

// --- Arranque ---

static void ruta(const char *uri, httpd_method_t metodo, esp_err_t (*h)(httpd_req_t *))
{
    httpd_uri_t u = { .uri = uri, .method = metodo, .handler = h };
    httpd_register_uri_handler(servidor, &u);
}

void web_iniciar(void)
{
    cerrojo = xSemaphoreCreateMutex();
    httpd_config_t c = HTTPD_DEFAULT_CONFIG();
    c.max_open_sockets = 10;
    c.max_uri_handlers = 32;
    c.lru_purge_enable = true;
    c.uri_match_fn = httpd_uri_match_wildcard;
    c.stack_size = 16384;
    c.core_id = 0;
    c.recv_wait_timeout = 10;
    c.keep_alive_enable = true;
    c.send_wait_timeout = 5;
    if (httpd_start(&servidor, &c) != ESP_OK) {
        ESP_LOGE(TAG, "No se pudo arrancar el servidor web");
        return;
    }
    ruta("/", HTTP_GET, h_raiz);
    ruta("/p", HTTP_GET, h_pagina);
    ruta("/index.html", HTTP_GET, h_pagina);
    ruta("/icono.png", HTTP_GET, h_icono);
    ruta("/portal", HTTP_GET, h_portal);
    ruta("/portal/ok", HTTP_GET, h_portal_ok);
    // Comprobaciones de portal cautivo de iPhone/Mac, Android, Windows y Firefox
    ruta("/hotspot-detect.html", HTTP_GET, h_sonda);
    ruta("/library/test/success.html", HTTP_GET, h_sonda);
    ruta("/generate_204", HTTP_GET, h_sonda);
    ruta("/gen_204", HTTP_GET, h_sonda);
    ruta("/connecttest.txt", HTTP_GET, h_sonda);
    ruta("/ncsi.txt", HTTP_GET, h_sonda);
    ruta("/success.txt", HTTP_GET, h_sonda);
    ruta("/estado", HTTP_GET, h_estado);
    ruta("/perfil", HTTP_GET, h_perfil);
    ruta("/medidor", HTTP_GET, h_medidor);
    ruta("/movil", HTTP_GET, h_movil);
    ruta("/eventos", HTTP_GET, h_eventos);
    ruta("/api", HTTP_POST, h_api);
    ruta("/wifi", HTTP_GET, h_wifi);
    ruta("/wifi", HTTP_POST, h_wifi_post);
    ruta("/firmware", HTTP_POST, h_firmware);
    ruta("/*", HTTP_GET, h_resto);                          // lo demás: portal (si es otro dominio) o 404
    xTaskCreatePinnedToCore(tarea_directo, "directo", 16384, NULL, 4, NULL, 0);
    ESP_LOGI(TAG, "Servidor web listo (puerto 80)");
}
