# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

La página que sirve el Mac al móvil y al iPad (`app/Pagina.swift`) es la superficie principal. La app de macOS en SwiftUI (`app/Vistas.swift`) es una superficie nativa secundaria. La placa sirve esa misma página por WiFi, con su portal cautivo en `main/web.c`. La app de escritorio Tauri (`escritorio/`) es aparte: instala el firmware.

La **web pública** (`web/`, publicada en p5k-ps5.github.io) es una superficie aparte, de presentación: explica el proyecto y guía para fabricarse uno. La placa propia lleva su QR grabado.

## Users

Una sola persona: el dueño del proyecto, que juega en PS5 con su DualSense pasando por el Mac y una ESP32-S3. No es un producto para vender: la app no tiene que explicarse a desconocidos, pero sí ser rápida y clara para quien la usa a diario.

La web pública es la excepción: es para quien no conoce el proyecto y quiere hacerse uno (jugadores y makers), que llega por el QR de la placa (casi siempre desde el móvil) o por un enlace. Tiene que entender en segundos qué hace la placa y luego tener una guía clara para fabricarla (placa de JLCPCB o montaje con módulos). El proyecto es libre (GPL-3.0).

## Product Purpose

Lee el DualSense en el Mac, aplica el perfil activo unas 1000 veces por segundo (sticks, gatillos, reasignación, turbo, macros, anti-recoil, ayuda al apuntado) y manda el resultado a la ESP32, que se presenta a la consola como un mando de PS4 a través del P5Mate. Funciona bien cuando cambiar algo a mitad de partida cuesta un toque y no hay que soltar el mando más de un segundo.

## Positioning

El puente está hecho a medida: perfiles, widgets y ajustes finos que cambian en directo, con la medida de tu propio control. Es una herramienta personal de taller, no una app de consumo.

## Operating Context

- Durante la partida la pantalla del Mac muestra la PS5, así que la ventana del Mac casi no se ve.
- Los ajustes se tocan en el **móvil y en el iPad**, a mano, entre ráfagas, a menudo con poca luz y con el mando en la otra mano. A veces, desde un ordenador (la página en el navegador, también en Windows, o la ventana del Mac) sin móvil ni iPad.
- La ventana del Mac se usa sobre todo para preparar perfiles con calma, sin estar jugando.
- Los avisos llegan por voz desde el Mac o, con la voz apagada, como un toast en la ventana y en el móvil.
- Red local de casa, con una clave; sin internet.

## Capabilities and Constraints

- macOS 13 como mínimo; se compila con `swiftc` sin Xcode; sin dependencias externas.
- La página del móvil es un único HTML con CSS, JS y fuentes embebidos en Swift; sin frameworks ni CDNs (no hay internet garantizado). Va también dentro del firmware: lo que pese, pesa allí.
- Todo en español.
- El diseño no cambia la lógica, el protocolo serie ni el formato de `perfiles.json`.
- Secciones: En vivo (mandos en directo y widgets), Sticks, Gatillos, Botones, Turbo, Macros, Anti-recoil, Ayuda al apuntado, Mi control, Perfiles, Móvil (solo Mac), Ayuda.
- En el móvil, En vivo se refresca cada 50 ms con eventos del servidor.

## Brand Commitments

- Identidad: **la misma que NeuroClaude** y las demás apps del usuario (negro, lima `#C8F04D`, Inter Tight y Geist Mono). La referencia es `~/Developer/cabina`.
- El icono sigue su sistema (baldosa negra y símbolo en lima) con un símbolo propio: el mando.
- Se conserva de antes la rejilla de teclas grandes: es lo que se toca jugando.
- La página se usa en el móvil, en el iPad y en el navegador de cualquier ordenador (también Windows); la ventana de la app de Mac tiene que estar a la misma altura.

## Evidence on Hand

No hay capturas, usuarios ni datos de uso aparte del propio código y las pruebas (`pruebas/`). No inventar cifras ni testimonios.

## Product Principles

1. **Un toque a mitad de partida.** Lo que se cambia jugando (widgets, perfil, pausa) se alcanza con un dedo, en grande, sin buscar.
2. **El estado se lee de un vistazo.** Qué está encendido y qué recibe la consola tiene que verse sin leer.
3. **Afinar con calma, en otro sitio.** Los ajustes finos pueden ser densos, pero ordenados y con valores exactos.
4. **Nunca engañar sobre lo que pasa.** Si la placa o el mando no están, se dice claro; nada aparenta funcionar si no funciona.

## Accessibility & Inclusion

Uso con poca luz y a distancia de brazo: contraste alto, objetivos táctiles grandes, nada que dependa solo del color.
