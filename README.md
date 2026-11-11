# p5k-ps5

**Web: [p5k-ps5.github.io](https://p5k-ps5.github.io)** · Licencia [GPL-3.0](LICENSE)

Una placa abierta que va entre tu DualSense y la PS5 (a través de un adaptador P5Mate) y aplica tu perfil
(sticks, gatillos, botones, turbo, macros, anti-recoil y ayuda al apuntado) mil veces por segundo, ajustable desde
el móvil por WiFi.

```
DualSense --USB--> placa p5k-ps5 (MAX3421E + ESP32-S3) --USB--> P5Mate --> PS5
                                    `--WiFi--> la app en el móvil
```

| Carpeta | Qué hay |
|---|---|
| `main/`, `components/motor/` | Firmware del ESP32-S3 (ESP-IDF) y el motor en Rust que aplica el perfil |
| `placa/` | La placa propia: esquema, PCB y archivos de fabricación para JLCPCB ([LEEME](placa/LEEME.md)) |
| `caja/` | Cajas impresas en 3D para el montaje con módulos ([LEEME](caja/LEEME.md)) |
| `escritorio/` | App de escritorio (Windows y macOS): graba el firmware y puede hacer de puente |
| `app/` | App nativa de macOS (SwiftUI) |
| `web/` | La web del proyecto (se publica en p5k-ps5.github.io) |

> **Anti-recoil y ayuda al apuntado: solo para modos sin conexión** (campaña, zombis, partidas contra bots). En
> partidas online es hacer trampas y el anti-trampas lo detecta; usarlos ahí puede costarte la cuenta.

Originalmente el puente era el Mac en medio:

```
DualSense --Bluetooth--> app del Mac --serie--> ESP32-S3 --USB--> consola (con un adaptador con licencia)
```

## Firmware

Firmware para una placa ESP32-S3 (probado en una GERUI ESP32-S3 WROOM-1 N16R8 DevKitC-1) que se presenta
por USB como un **mando de PS4** (DualShock 4, VID `054C`, PID `09CC`) y envía su estado a 1000 Hz.
El estado del mando le llega desde un ordenador por el puerto serie, o con órdenes de texto para probarlo.

## Qué hace
- **USB nativo → mando de PS4** (TinyUSB, HID). Responde a las peticiones de configuración habituales
  (calibración, tipo de mando, dirección, versión). **No** contesta a la autenticación de PS4/PS5: para
  usarlo en una consola hace falta un adaptador con licencia que se encargue de eso.
- **Dos modos**, guardados en memoria:
  - `mac`: mando + puerto serie por el mismo cable USB (para probar con el ordenador).
  - `consola`: solo mando.
- **LED RGB (GPIO48)**: rojo = sin conectar · verde = conectado en modo mac · cian = conectado en modo
  consola · destello azul = el aparato ha pedido datos de configuración.
- **Botón BOOT**: pulsación corta = botón ✕ · mantener 2 s = cambiar de modo.

## Tramas del ordenador
Por el puerto serie (el «COM» a 921600 baudios, o el puerto serie USB en modo mac):

```
A5 5A | botones (2 bytes, bajo primero) | cruceta | lx | ly | rx | ry | l2 | r2 | XOR de esos 9 bytes
```

- Botones en el orden de bits del DualShock 4: □ ✕ ○ △ L1 R1 L2 R2 Share Options L3 R3 PS táctil.
- Cruceta: 0 = arriba y en sentido horario hasta 7; 8 = suelta.
- Sticks y gatillos de 0 a 255 (128 = centro de los sticks).
- Si dejan de llegar tramas durante 250 ms, el mando vuelve al centro.

## La placa sin ordenador
Con un DualSense conectado por USB a un MAX3421E (host USB por SPI), la placa hace lo mismo que la app
de escritorio, sin ordenador: aplica el perfil (anti-recoil, ayuda al apuntado, turbo, macros, sticks,
gatillos, botones…) y sirve **la misma app web por WiFi**. El motor es el mismo código Rust que la app de
escritorio (`components/motor`). La WiFi tiene onboarding: si no hay red de casa configurada (o deja de
funcionar), la placa abre su propia red, **p5k-ps5 XXXX**, y el móvil abre la página solo al
conectarse. En casa, la placa está en **http://puente.local**. Detalles y API en `PLACA-WEB.md`.

```
DualSense --USB--> MAX3421E --SPI--> ESP32-S3 (motor + app web) --USB--> PS5 (modo dualsense)
                                                                      --> P5Mate --> consola (modo consola)
```

## Órdenes de texto (por el mismo puerto)
`ayuda`, `pulsa <botón> [ms]`, `manten <botón>`, `suelta [botón]`, `stick <izq|der> <x> <y>`,
`gatillo <l2|r2> <0-100>`, `demo`, `estado` (modo, WiFi y clave de la app web), `modo <mac|consola|dualsense>`,
`wifi` (estado y redes), `wifi buscar`, `wifi olvidar` (abre la red propia), `medir` (cuánto tarda el
motor), `grabar` (reinicia en modo grabación), `reinicia`.

## Compilar y grabar
Con ESP-IDF 5.5 y la toolchain de Rust para el ESP32-S3 (el motor, `components/motor`, se compila con
cargo durante `idf.py build`):

```bash
cargo install espup --locked && espup install --targets esp32s3   # una vez
idf.py set-target esp32s3
idf.py build
idf.py -p /dev/cu.usbmodemXXXX flash monitor
```

Las pruebas del motor se ejecutan en el ordenador: `cd components/motor && cargo +stable test --target aarch64-apple-darwin --lib`.
Con la placa ya en marcha, el firmware también se puede actualizar por WiFi desde la pestaña Placa
(`build/puente_mando.bin`).

Si la placa está en el USB nativo con este firmware, entra en modo grabación con la orden `grabar` (o
manteniendo BOOT y pulsando RST) y, tras grabar, reinicia con `--after watchdog_reset` en esptool.

## App de macOS

App nativa en SwiftUI (macOS 13 o posterior). No hace falta Xcode: basta con las herramientas de
línea de órdenes de Apple.

```bash
./construir_app.sh      # crea «p5k-ps5.app» en esta carpeta
./ejecutar_pruebas.sh   # pruebas automáticas del motor
```

- Lee el DualSense con el framework GameController y aplica el perfil activo unas 1000 veces por
  segundo: sticks, gatillos, reasignación, turbo, macros, anti-recoil y ayuda al apuntado.
- Perfiles guardados en `~/Library/Application Support/Puente de mando/perfiles.json`.
- Servidor web local, solo para la red de casa y protegido con clave, para ver y ajustar todo desde el móvil.
- «Mi control»: mide tu propio stick mientras disparas, para practicar.
- `mac/prueba_mando.py` comprueba desde el Mac que la placa responde como mando (necesita `hidapi` y `pyserial`).

Pensada para modos sin conexión. En partidas online, usar anti-recoil o macros es hacer trampas y los
anti-trampas lo detectan.

## App de escritorio (Windows y macOS)

Carpeta `escritorio/` (Tauri 2: Rust + interfaz web). Es el **puente completo**, sin necesitar el Mac:

- Lee el DualSense (USB o Bluetooth), aplica el perfil activo (sticks, gatillos, botones, turbo, macros,
  anti-recoil fijo, progresivo o por patrón, ayuda al apuntado, widgets y combinaciones del mando) unas 1000 veces
  por segundo y lo manda a la ESP32. El procesador es un port de `app/Procesador.swift` y da la misma salida byte a
  byte (`cargo test --lib procesador`, con los casos que genera `src-tauri/pruebas/generar.sh` desde el de Swift).
- Usa el mismo `perfiles.json` que la app de Mac (en Windows, en `%APPDATA%\Puente de mando`).
- Sirve la misma página que el móvil y el iPad (sacada de `app/Pagina.swift` al compilar) en el puerto 8787; la
  ventana de la app es esa misma página. Avisos con la voz del sistema o en pantalla.
- Al abrirla por primera vez guía para grabar el firmware en la ESP32-S3 y comprar el **P5Mate**; el menú «Puente»
  lleva al panel, al asistente del firmware y a la dirección para el móvil.

```bash
cd escritorio && npm install
npm run dev                 # la app en modo desarrollo (necesita Rust)
npm run build               # instalador del sistema en el que estés (.dmg en Mac)
./construir_windows.sh      # instalador de Windows (.exe) desde el Mac
```

Tiene todo lo de la app de Mac: también «Mi control», el monitor de la señal y las secciones Móvil y Ayuda. Para probar la app nueva junto a la de Mac sin tocar nada suyo: `PUENTE_ARCHIVO`
(otra copia de los perfiles), `PUENTE_PUERTO` (otro puerto) y `PUENTE_SIN_PLACA=1` (no abrir la placa). No abras
las dos apps a la vez con la placa: las dos le mandarían el mando.

En Windows, la primera vez el cortafuegos pregunta si deja entrar conexiones: permite las **redes privadas** para
que el móvil y el iPad puedan abrir el panel. Sin firmar, Windows enseña el aviso de SmartScreen («Más información
→ Ejecutar de todas formas»).

## Licencia
Todo el proyecto (firmware, apps, placa, caja y web) se publica con la licencia
[GNU GPL v3](LICENSE). Las fuentes Inter Tight y Geist Mono tienen su propia licencia, la SIL Open Font
License 1.1 (viaja dentro de cada fuente).

Proyecto personal, sin relación con Sony Interactive Entertainment. PlayStation, PS5 y DualSense son marcas de
sus dueños.

## Créditos
El descriptor HID y las respuestas de configuración del DualShock 4 están basados en
[GP2040-CE](https://github.com/OpenStickCommunity/GP2040-CE) (licencia MIT, OpenStickCommunity).
