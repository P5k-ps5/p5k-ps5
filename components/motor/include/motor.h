// El motor en Rust (components/motor/src, el mismo código que la app de escritorio): lo que el firmware
// en C le pide. Los textos que devuelve se devuelven con motor_liberar().
#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

// Estado del mando. Botones: un bit por botón, en el orden de modelo::Boton:
// □ ✕ ○ △ L1 R1 L2 R2 Share Options L3 R3 PS Táctil ↑ → ↓ ← Mic (bit 0 a 18)
typedef struct {
    uint32_t botones;
    uint8_t lx, ly, rx, ry;   // 0..255, 128 = centro, Y pequeña = arriba
    uint8_t l2, r2;           // gatillos 0..255
} motor_estado_t;

enum {
    MB_CUADRADO, MB_X, MB_CIRCULO, MB_TRIANGULO, MB_L1, MB_R1, MB_L2, MB_R2,
    MB_SHARE, MB_OPTIONS, MB_L3, MB_R3, MB_PS, MB_TACTIL,
    MB_ARRIBA, MB_DERECHA, MB_ABAJO, MB_IZQUIERDA, MB_SILENCIAR,
};

void motor_iniciar(const char *carpeta);                 // carga perfiles.json y medidor.json
motor_estado_t motor_vuelta(const motor_estado_t *entrada, int64_t t_us);   // entrada NULL: sin mando
void motor_lento(void);                                  // guardar cambios y analizar ráfagas (cada poco)
void motor_poner_mando(bool conectado, int32_t hz, float hueco_ms, int32_t bateria, uint8_t estado_bateria,
                       int32_t envios);
bool motor_leer_dualsense(const uint8_t *informe, size_t largo, motor_estado_t *salida,
                          int32_t *bateria, uint8_t *estado_bateria);
size_t motor_informe_luz(uint8_t r, uint8_t g, uint8_t b, bool preparar, uint8_t *destino, size_t cabe);
bool motor_destello(uint8_t rgb[3]);
bool motor_color(uint8_t rgb[3]);                       // color del perfil activo

char *motor_instantanea(void);                           // GET /estado y /eventos
char *motor_perfil(void);                                // GET /perfil
char *motor_medidor(void);                               // GET /medidor
char *motor_aplicar(const char *json);                   // POST /api
char *motor_clave(void);
char *motor_revision(void);
char *motor_qr_svg(const char *texto);
// Sincronización con las apps: los ajustes (perfiles, activo, generales sin clave) en JSON compacto
char *motor_ajustes(void);
char *motor_revision_ajustes(const char *json);
char *motor_poner_ajustes(const char *json);       // «OK <revisión>» o «ERROR <motivo>»
float motor_medir(uint32_t vueltas, float *peor_us);       // µs por vuelta del procesador
void motor_liberar(char *s);
