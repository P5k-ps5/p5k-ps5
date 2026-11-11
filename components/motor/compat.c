// Funciones que la std de Rust referencia y ESP-IDF no trae. No se usan en el motor.
#include <errno.h>
#include <stddef.h>

char *realpath(const char *ruta, char *resuelta)
{
    (void)ruta;
    (void)resuelta;
    errno = ENOSYS;
    return NULL;
}
