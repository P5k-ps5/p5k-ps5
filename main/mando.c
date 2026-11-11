// Estado del mando: lo cambian las órdenes y lo lee la tarea que envía los informes por USB.

#include "freertos/FreeRTOS.h"
#include "esp_timer.h"
#include "puente.h"

static portMUX_TYPE cerrojo = portMUX_INITIALIZER_UNLOCKED;
static mando_t mando = {
    .dpad = DPAD_CENTRO, .lx = 128, .ly = 128, .rx = 128, .ry = 128,
};
static int64_t soltar_en[NUM_BOTONES];   // µs desde el arranque; 0 = no caduca
static int64_t dpad_soltar_en;
static int64_t externo_hasta;            // mientras lleguen tramas del Mac; 0 = no hay

// Si el programa del Mac deja de mandar (se cierra o se cae), el mando vuelve al centro
#define EXTERNO_CADUCA_US (250 * 1000)

// Llamar con el cerrojo cogido
static void soltar(int boton)
{
    mando.botones &= ~(1u << boton);
    soltar_en[boton] = 0;
    if (boton == BTN_L2) mando.l2 = 0;
    if (boton == BTN_R2) mando.r2 = 0;
}

static uint8_t eje(int valor)   // -100..100 -> 0..255
{
    if (valor < -100) valor = -100;
    if (valor > 100) valor = 100;
    return (uint8_t)(128 + (valor * 127) / 100);
}

void mando_pulsar(int boton, int ms)
{
    if (boton < 0 || boton >= NUM_BOTONES) return;
    int64_t limite = ms > 0 ? esp_timer_get_time() + ms * 1000LL : 0;
    taskENTER_CRITICAL(&cerrojo);
    mando.botones |= 1u << boton;
    soltar_en[boton] = limite;
    if (boton == BTN_L2) mando.l2 = 255;   // el mando real marca el gatillo a fondo
    if (boton == BTN_R2) mando.r2 = 255;
    taskEXIT_CRITICAL(&cerrojo);
}

void mando_soltar(int boton)
{
    if (boton < 0 || boton >= NUM_BOTONES) return;
    taskENTER_CRITICAL(&cerrojo);
    soltar(boton);
    taskEXIT_CRITICAL(&cerrojo);
}

void mando_dpad(int dir, int ms)
{
    int64_t limite = ms > 0 ? esp_timer_get_time() + ms * 1000LL : 0;
    taskENTER_CRITICAL(&cerrojo);
    mando.dpad = (uint8_t)dir;
    dpad_soltar_en = limite;
    taskEXIT_CRITICAL(&cerrojo);
}

void mando_stick(bool derecho, int x, int y)
{
    taskENTER_CRITICAL(&cerrojo);
    if (derecho) { mando.rx = eje(x); mando.ry = eje(-y); }
    else         { mando.lx = eje(x); mando.ly = eje(-y); }
    taskEXIT_CRITICAL(&cerrojo);
}

void mando_gatillo(bool derecho, int valor)
{
    if (valor < 0) valor = 0;
    if (valor > 100) valor = 100;
    uint8_t v = (uint8_t)(valor * 255 / 100);
    int boton = derecho ? BTN_R2 : BTN_L2;
    taskENTER_CRITICAL(&cerrojo);
    if (derecho) mando.r2 = v; else mando.l2 = v;
    if (v > 0) mando.botones |= 1u << boton; else mando.botones &= ~(1u << boton);
    soltar_en[boton] = 0;
    taskEXIT_CRITICAL(&cerrojo);
}

// Llamar con el cerrojo cogido
static void todo_al_centro(void)
{
    for (int b = 0; b < NUM_BOTONES; b++) soltar(b);
    mando.dpad = DPAD_CENTRO;
    dpad_soltar_en = 0;
    mando.lx = mando.ly = mando.rx = mando.ry = 128;
    externo_hasta = 0;
}

void mando_soltar_todo(void)
{
    taskENTER_CRITICAL(&cerrojo);
    todo_al_centro();
    taskEXIT_CRITICAL(&cerrojo);
}

void mando_poner(const mando_t *m)
{
    int64_t ahora = esp_timer_get_time();
    taskENTER_CRITICAL(&cerrojo);
    mando = *m;
    for (int b = 0; b < NUM_BOTONES; b++) soltar_en[b] = 0;
    dpad_soltar_en = 0;
    externo_hasta = ahora + EXTERNO_CADUCA_US;
    taskEXIT_CRITICAL(&cerrojo);
}

void mando_copiar(mando_t *salida)
{
    int64_t ahora = esp_timer_get_time();
    taskENTER_CRITICAL(&cerrojo);
    if (externo_hasta && ahora >= externo_hasta) todo_al_centro();
    for (int b = 0; b < NUM_BOTONES; b++) {
        if (soltar_en[b] && ahora >= soltar_en[b]) soltar(b);
    }
    if (dpad_soltar_en && ahora >= dpad_soltar_en) {
        mando.dpad = DPAD_CENTRO;
        dpad_soltar_en = 0;
    }
    *salida = mando;
    taskEXIT_CRITICAL(&cerrojo);
}
