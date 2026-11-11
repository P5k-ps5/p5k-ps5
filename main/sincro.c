// Sincronización de los ajustes con las apps del ordenador, por el mismo cable serie de siempre (el COM, o el
// puerto serie USB en modo mac). La placa guarda los ajustes «buenos»; cada app los lee al conectarse y le
// manda sus cambios. Va en líneas de texto cortas (base64) para no frenar las tramas del mando, que siguen
// llegando por el mismo cable. Las respuestas empiezan por «@AJ » para distinguirlas de los mensajes del log.
//
//   ajustes rev                  -> @AJ REV <revisión> <bytes> <crc32>   (y guarda una copia para leerla)
//   ajustes leer <desde>         -> @AJ T <desde> <base64 de hasta TROZO bytes de esa copia>
//   ajustes poner <bytes> <crc32>-> @AJ LISTO
//   ajustes trozo <desde> <b64>  -> @AJ ACK <recibidos>          (si <desde> no es lo esperado, no lo añade)
//   ajustes fin                  -> @AJ OK <revisión nueva>  o  @AJ ERROR <motivo>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include "mbedtls/base64.h"
#include "motor.h"
#include "puente.h"

#define TROZO 150                  // bytes por línea (200 caracteres en base64)
#define MAXIMO (256 * 1024)        // ajustes más grandes que esto no se aceptan

static char *copia;                // lo último que se pidió con «rev» (lo que se va leyendo a trozos)
static size_t largo_copia;
static uint8_t *entrada;           // lo que va mandando la app con «trozo»
static size_t esperado, recibido;
static uint32_t crc_esperado;

// CRC-32 normal (el de zlib): así lo calculan igual la app de Mac (Swift) y la de escritorio (Rust)
static uint32_t crc32(const uint8_t *d, size_t n)
{
    uint32_t c = 0xFFFFFFFF;
    for (size_t i = 0; i < n; i++) {
        c ^= d[i];
        for (int k = 0; k < 8; k++) c = (c & 1) ? (c >> 1) ^ 0xEDB88320 : c >> 1;
    }
    return ~c;
}

static void rev(void)
{
    free(copia);
    copia = motor_ajustes();
    largo_copia = copia ? strlen(copia) : 0;
    char *r = motor_revision_ajustes(copia);
    responder("@AJ REV %s %u %08lx", r ? r : "?", (unsigned)largo_copia,
              (unsigned long)crc32((const uint8_t *)copia, largo_copia));
    motor_liberar(r);
}

static void leer(size_t desde)
{
    if (!copia || desde >= largo_copia) { responder("@AJ T %u", (unsigned)desde); return; }
    size_t n = largo_copia - desde < TROZO ? largo_copia - desde : TROZO;
    unsigned char b64[TROZO * 4 / 3 + 8];
    size_t escrito = 0;
    mbedtls_base64_encode(b64, sizeof(b64), &escrito, (const unsigned char *)copia + desde, n);
    b64[escrito] = 0;
    responder("@AJ T %u %s", (unsigned)desde, (char *)b64);
}

static void poner(size_t bytes, uint32_t crc)
{
    free(entrada);
    entrada = NULL;
    if (bytes == 0 || bytes > MAXIMO || !(entrada = malloc(bytes + 1))) {
        responder("@AJ ERROR tamaño no válido");
        return;
    }
    esperado = bytes;
    recibido = 0;
    crc_esperado = crc;
    responder("@AJ LISTO");
}

static void trozo(size_t desde, const char *b64)
{
    if (!entrada) { responder("@AJ ERROR falta «ajustes poner»"); return; }
    if (desde == recibido) {
        size_t n = 0;
        if (mbedtls_base64_decode(entrada + recibido, esperado - recibido, &n, (const unsigned char *)b64, strlen(b64)) == 0) {
            recibido += n;
        }
    }
    responder("@AJ ACK %u", (unsigned)recibido);
}

static void fin(void)
{
    if (!entrada || recibido != esperado) { responder("@AJ ERROR faltan datos (%u de %u)", (unsigned)recibido, (unsigned)esperado); return; }
    if (crc32(entrada, recibido) != crc_esperado) {
        responder("@AJ ERROR los datos han llegado mal (CRC)");
        free(entrada);
        entrada = NULL;
        return;
    }
    entrada[recibido] = 0;
    char *r = motor_poner_ajustes((const char *)entrada);
    free(entrada);
    entrada = NULL;
    responder("@AJ %s", r ? r : "ERROR sin respuesta del motor");
    motor_liberar(r);
}

// Devuelve true si era una orden «ajustes ...»
bool sincro_orden(char *palabras[], int n)
{
    if (n < 2 || strcasecmp(palabras[0], "ajustes")) return false;
    const char *que = palabras[1];
    if (!strcasecmp(que, "rev")) rev();
    else if (!strcasecmp(que, "leer") && n >= 3) leer(strtoul(palabras[2], NULL, 10));
    else if (!strcasecmp(que, "poner") && n >= 4) poner(strtoul(palabras[2], NULL, 10), strtoul(palabras[3], NULL, 16));
    else if (!strcasecmp(que, "trozo") && n >= 4) trozo(strtoul(palabras[2], NULL, 10), palabras[3]);
    else if (!strcasecmp(que, "fin")) fin();
    else responder("@AJ ERROR orden no válida");
    return true;
}
