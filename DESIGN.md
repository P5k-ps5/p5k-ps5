---
name: p5k-ps5
description: Panel del mando y web pública con la misma estética que NeuroClaude; negro, línea fina y un solo acento lima.
colors:
  negro: "#000000"
  tinta: "#0a0a0a"
  blanco: "#ffffff"
  vivo: "#c8f04d"
  vivo-suave: "rgba(200,240,77,.08)"
  fallo: "#ff5d5d"
  texto-suave: "rgba(255,255,255,.68)"
  texto-tenue: "rgba(255,255,255,.46)"
  linea-fina: "rgba(255,255,255,.1)"
  linea: "rgba(255,255,255,.16)"
  linea-fuerte: "rgba(255,255,255,.36)"
typography:
  titular:
    fontFamily: '"Inter Tight", -apple-system, system-ui, sans-serif'
    fontSize: "clamp(30px, 4.4vw, 46px)"
    fontWeight: 500
    lineHeight: 1
    letterSpacing: "-0.03em"
  body:
    fontFamily: '"Inter Tight", -apple-system, system-ui, sans-serif'
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.42
  intro:
    fontFamily: '"Inter Tight", -apple-system, system-ui, sans-serif'
    fontSize: "15px"
    fontWeight: 400
  secundario:
    fontFamily: '"Inter Tight", -apple-system, system-ui, sans-serif'
    fontSize: "13px"
    fontWeight: 400
  campo-tactil:
    fontFamily: '"Geist Mono", ui-monospace, SFMono-Regular, Menlo, monospace'
    fontSize: "16px"
    fontWeight: 300
  etiqueta:
    fontFamily: '"Geist Mono", ui-monospace, SFMono-Regular, Menlo, monospace'
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "0.06em"
  dato:
    fontFamily: '"Geist Mono", ui-monospace, SFMono-Regular, Menlo, monospace'
    fontSize: "12px"
    fontWeight: 300
    lineHeight: 1.3
  web-titular:
    fontFamily: '"Inter Tight", -apple-system, "Segoe UI", system-ui, sans-serif'
    fontSize: "clamp(40px, 5.2vw, 72px)"
    fontWeight: 500
    lineHeight: 1
    letterSpacing: "-0.035em"
  web-seccion:
    fontFamily: '"Inter Tight", -apple-system, "Segoe UI", system-ui, sans-serif'
    fontSize: "clamp(30px, 4.4vw, 52px)"
    fontWeight: 500
    lineHeight: 1.02
    letterSpacing: "-0.03em"
  web-subtitulo:
    fontFamily: '"Inter Tight", -apple-system, "Segoe UI", system-ui, sans-serif'
    fontSize: "18px"
    fontWeight: 500
    lineHeight: 1.25
    letterSpacing: "-0.015em"
  web-entrada:
    fontFamily: '"Inter Tight", -apple-system, "Segoe UI", system-ui, sans-serif'
    fontSize: "clamp(17px, 1.35vw, 19px)"
    fontWeight: 400
    lineHeight: 1.5
  web-body:
    fontFamily: '"Inter Tight", -apple-system, "Segoe UI", system-ui, sans-serif'
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.55
  web-titulo-caja:
    fontFamily: '"Inter Tight", -apple-system, "Segoe UI", system-ui, sans-serif'
    fontSize: "22px"
    fontWeight: 500
    lineHeight: 1.1
    letterSpacing: "-0.02em"
  web-numero-paso-movil:
    fontFamily: '"Geist Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace'
    fontSize: "24px"
    fontWeight: 300
    lineHeight: 1
  web-numero-paso:
    fontFamily: '"Geist Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace'
    fontSize: "34px"
    fontWeight: 300
    lineHeight: 1
rounded:
  caja: "0"
  pildora: "999px"
  telefono: "52px"
  telefono-pantalla: "42px"
  telefono-movil: "40px"
  telefono-pantalla-movil: "30px"
spacing:
  xs: "4px"
  sm: "6px"
  md: "8px"
  lg: "12px"
  caja: "14px"
  columna: "24px"
  web-margen: "clamp(16px, 4vw, 48px)"
  web-ancho: "1240px"
  web-seccion: "clamp(72px, 11vh, 128px)"
components:
  button:
    backgroundColor: "rgba(255,255,255,.08)"
    textColor: "{colors.blanco}"
    typography: "{typography.dato}"
    rounded: "{rounded.caja}"
    padding: "6px 12px"
    height: "34px (44px en táctil)"
  button-primary:
    backgroundColor: "{colors.blanco}"
    textColor: "{colors.negro}"
    rounded: "{rounded.pildora}"
    padding: "6px 16px"
  button-danger:
    backgroundColor: "{colors.fallo}"
    textColor: "{colors.negro}"
    rounded: "{rounded.caja}"
  card:
    backgroundColor: "{colors.negro}"
    textColor: "{colors.blanco}"
    rounded: "{rounded.caja}"
    padding: "0 14px 12px"
  tecla:
    backgroundColor: "{colors.negro}"
    textColor: "{colors.blanco}"
    rounded: "{rounded.caja}"
    padding: "12px"
    height: "128px (112px en móvil)"
  tecla-on:
    backgroundColor: "{colors.vivo-suave}"
    textColor: "{colors.vivo}"
  web-pildora:
    backgroundColor: "{colors.blanco}"
    textColor: "{colors.negro}"
    rounded: "{rounded.pildora}"
    padding: "0 26px"
    height: "48px"
  web-pildora-hover:
    backgroundColor: "rgba(255,255,255,.86)"
    textColor: "{colors.negro}"
  web-pildora-linea:
    backgroundColor: "{colors.negro}"
    textColor: "{colors.blanco}"
    rounded: "{rounded.pildora}"
    padding: "0 26px"
    height: "48px"
  web-telefono:
    backgroundColor: "{colors.negro}"
    rounded: "{rounded.telefono}"
    padding: "10px"
    size: "390 × 780px (en móvil, todo el ancho y 390/600)"
  web-telefono-pantalla:
    backgroundColor: "{colors.negro}"
    rounded: "{rounded.telefono-pantalla}"
  web-salto:
    backgroundColor: "transparent"
    textColor: "{colors.blanco}"
    typography: "{typography.web-subtitulo}"
    padding: "14px 0"
  web-salto-on:
    textColor: "{colors.vivo}"
  web-tz-demo:
    backgroundColor: "transparent"
    textColor: "{colors.texto-suave}"
    rounded: "{rounded.caja}"
    padding: "0 16px"
    height: "48px"
  web-instalador:
    backgroundColor: "{colors.vivo-suave}"
    textColor: "{colors.blanco}"
    rounded: "{rounded.caja}"
    padding: "12px 16px"
  web-pieza-estado:
    backgroundColor: "{colors.negro}"
    textColor: "{colors.blanco}"
    rounded: "{rounded.caja}"
    padding: "14px 16px 16px"
    height: "168px mínimo (libre en móvil)"
  web-pieza-estado-on:
    backgroundColor: "{colors.vivo-suave}"
    textColor: "{colors.vivo}"
  web-codigo:
    backgroundColor: "transparent"
    textColor: "{colors.blanco}"
    rounded: "{rounded.caja}"
    padding: "16px 18px"
  web-marcador:
    backgroundColor: "transparent"
    rounded: "{rounded.caja}"
    size: "9px (zona táctil de 44px)"
  web-marcador-on:
    backgroundColor: "{colors.vivo}"
    rounded: "{rounded.caja}"
    size: "9px"
  web-tecla-funciones:
    backgroundColor: "{colors.negro}"
    textColor: "{colors.blanco}"
    rounded: "{rounded.caja}"
    padding: "12px 16px"
  web-solo-sin-conexion:
    backgroundColor: "transparent"
    textColor: "{colors.blanco}"
    rounded: "{rounded.caja}"
    padding: "3px 7px"
  web-eslabon:
    backgroundColor: "{colors.negro}"
    textColor: "{colors.blanco}"
    rounded: "{rounded.caja}"
    padding: "20px 22px 22px"
  web-eslabon-vivo:
    backgroundColor: "{colors.vivo-suave}"
    textColor: "{colors.vivo}"
  web-pestana:
    backgroundColor: "transparent"
    textColor: "{colors.texto-suave}"
    rounded: "{rounded.caja}"
    padding: "0 18px"
    height: "48px"
  web-pestana-on:
    textColor: "{colors.vivo}"
---

# Design System: p5k-ps5

## Overview

**Estrella polar: "El mismo sistema operativo que NeuroClaude"**

p5k-ps5 forma parte de la misma familia que NeuroClaude, Lens, Rankeo, EcomCreative y Claude Stats. La referencia es `~/Developer/cabina` (`web/base.css`, `web/estilo.css`, `web/movil.css`, `app/icono.swift`): si hay duda sobre un detalle, se mira allí.

Fondo negro, texto blanco con opacidades y un único acento, el lima. Las superficies son cajas de línea fina sin relleno, sin sombras ni degradados. Inter Tight lleva lo que se lee y Geist Mono lleva etiquetas, datos y estados. La sensación es de sistema operativo vivo: puntos que laten, transiciones suaves y nada agresivo.

La identidad tiene dos superficies: la app del puente (en la placa, en el escritorio y en el Mac) y la **web pública** (`web/`, publicada en p5k-ps5.github.io). La web no es otro sistema: amplía este con una escala de titulares mayor, una página larga de lectura y componentes propios (el mapa del mando, la demo en su teléfono, la cadena del recorrido, los caminos de hardware, los pasos, el instalador y el tablero de estado). Lo que en este documento lleva «web» solo vale ahí.

En la app sigue mandando el uso: se toca a mano, a mitad de partida y con poca luz. Por eso lo denso es la letra, no los objetivos: en pantallas táctiles todo control mide 44 px y las teclas se acercan a un cuadrado grande. Lo que se toca jugando (teclas, perfil, Pausar) sigue arriba.

**Claves:**
- Negro puro; profundidad con línea, no con tono ni sombra.
- Un solo acento: lima para lo vivo y lo encendido; rojo solo para lo que falla o alarma.
- Sin radios, salvo las píldoras, los puntos y los objetos físicos redondos (el dibujo del DualSense y el marco del teléfono de la demo).
- Mono para todo lo que sea dato o etiqueta; mayúsculas con CSS o `textCase`, sin cambiar los textos.
- Una sola identidad: no hay tema claro, ni en la app ni en la web.
- En la web, el propio DualSense dibujado a línea es la portada y el índice.

## Colors

- **Negro** (`#000`): fondo de todo. **Tinta** (`#0a0a0a`): solo fondos de menús nativos.
- **Vivo** (`#c8f04d`): lo que está encendido, conectado o seleccionado; tramo del deslizador; sección activa; valores de los deslizadores; foco. Sobre él, el texto es negro. **Vivo suave** (lima al 8 %): fondo plano de lo encendido (tecla ON, el eslabón de la placa en la web).
- **En la web**, el lima marca: el control elegido en el mapa (marcador, forma del dibujo, línea guía, nombre y etiqueta de la tecla), el eslabón de la placa y el punto que viaja por el cable, el punto de «Probado con PS5», la pestaña elegida, la pregunta abierta (el «+» girado), el hover de enlaces y menú, el foco y el logo. Y además: la caja del instalador (borde lima y fondo lima al 8 %, porque es lo que de verdad hace algo con la placa), la tarjeta «Probado» del tablero (borde, fondo al 8 % y estado que late), el salto elegido de la demo (cuadrado lleno que late y nombre en lima; el nombre también pasa a lima en hover) y la flecha de «Ajústalo en la demo» en hover. Nada más.
- **Fallo** (`#ff5d5d`): sin conexión, borrar, toast de error, tecla de pausa encendida.
- **Blanco**: texto, acción principal y lo que pide atención sin ser un fallo (antes ámbar): punto blanco que parpadea y borde izquierdo de las notas.
- **Texto suave** (.68) y **tenue** (.46): explicaciones y etiquetas. La tenue no baja de .46, para mantener 4,5:1 sobre negro.
- **Líneas**: fina (.1) entre filas, normal (.16) en cajas y controles, fuerte (.36) en hover y en el dibujo de los sticks.

**La regla del lima único.** Ningún otro tono actúa ni decora. La acción principal es blanca, como en NeuroClaude: el lima no es «botón», es «esto está vivo». En la web vale igual: hay una píldora blanca llena por sección y nunca más, «Fabrícate uno» en la portada e «Instalar en la placa» en la caja del instalador; su hover baja el blanco al 86 % y nunca pasa a lima, ni siquiera dentro de la caja lima del instalador. «Abrir la demo» es una píldora de línea (negro con línea fuerte), porque solo abre la demo. Las dos excepciones son datos, no diseño: el color que el usuario elige para cada perfil (solo el punto del perfil y la luz del mando) y el fondo blanco del QR, que hace falta para escanearlo.

**La regla del estado con palabras.** El color confirma y la palabra informa: el punto lleva texto y la tecla lleva ON/OFF.

**Gráficas.** Dos series: horizontal en lima, vertical en blanco; la amplitud en gris. Sus textos de ayuda lo dicen así.

## Typography

Inter Tight (300 a 600) y Geist Mono (300 y 400), con licencia OFL. La página no tiene internet garantizado, así que **las fuentes van dentro**: recortes al español que genera `herramientas/fuentes.py` (43 KB de woff2 en base64 al final del `<head>`, entre las marcas `FUENTES`, y TTF por peso en `app/fuentes/` para la app de Mac). El portal cautivo de la placa no las lleva, porque se sirve aparte y tiene que pesar poco: usa la del sistema.

- **Titular** (500, 30 a 46 px, -0.03em): nombre de la sección. En «En vivo» no sale: ahí manda la rejilla de teclas.
- **Body** (400, 14 px): texto corriente. Introducciones a 15 px, ayudas a 12 px.
- **Etiqueta** (mono 400, 11 px, mayúsculas, 0.06em): cabecera de caja, grupos del índice.
- **Dato** (mono 300, 12 px): estados, direcciones, valores, botones (mono 400).
- **Campos**: mono 300 a 13 px; **16 px en táctil**, porque por debajo iOS hace zoom al enfocar.

### Escala de la web

La web lee más largo y desde más lejos, así que sube la escala; **estos tamaños son solo de la web** (en la app el titular se queda en 30 a 46 px):

- **Titular web** (500, 40 a 72 px, -0.035em, máx. 13ch): solo el h1 de la portada.
- **Sección web** (500, 30 a 52 px, -0.03em, máx. 18ch): un título por sección.
- **Subtítulo web** (500, 18 o 22 px, -0.015em): dos escalones. 18 px por defecto, también en los pasos de la guía; 22 px (`web-titulo-caja`) en los títulos de caja: cada camino, cada eslabón y el aviso. Las preguntas del FAQ van a 18 px y 400.
- **Entrada** (400, 17 a 19 px, 1.5, máx. 46ch) e **intro** de sección (17 px, máx. 60ch).
- **Texto web** (400, 16 px, 1.55, máx. 68ch, blanco al 68 %): 14 a 15 px dentro de componentes; 12 px solo en lo legal.
- **Etiquetas web**: las mismas de la app (mono 11 px, mayúsculas, 0.06em, tenue); las pestañas a 12 px y «Solo sin conexión» a 10,5 px.
- **Número de paso** (mono 300, 34 px; 24 px en móvil, tenue). Los **mini pasos** del instalador usan el mismo contador a 20 px.
- **Nombre de salto de la demo** y **nombre de pieza del tablero**: subtítulo web de 18 px; su texto a 14 px suave.
- **Rutas y código** (mono): las carpetas del mapa del repositorio en mono 400 de 14 px; el bloque de código en mono 300 de 13 px con interlínea 1.7. Pies de figura («Render 3D…», el de la demo) en mono 300 de 12 px, tenue.

La web sirve sus fuentes como woff2 propios en `web/fuentes/` (no base64, no de internet). Inter Tight y Geist Mono son la identidad fijada por el usuario: un detector que las marque como genéricas no es motivo para cambiarlas.

**Cifras.** Geist Mono ya es tabular: lo que cambia cada 50 ms no baila.

## Layout

Móvil: una columna con 12 px de margen; arriba perfil y Pausar, debajo los estados, y las pestañas en fila desplazable pegada arriba, con la activa subrayada en lima. Desde 960 px: cabecera con la marca a todo el ancho, índice de 210 px en una caja y contenido hasta 920 px. Desde 760 px los pares de controles van en dos columnas. La rejilla de teclas tiene 3 columnas en el móvil y se rellena con mínimo de 124 px desde 600 px.

La página no hace zoom en móvil ni iPad (`user-scalable=no`, `touch-action:manipulation` y bloqueo del pellizco).

**Web.** Página larga de una columna con ancho máximo de 1240 px y margen lateral de 16 a 48 px (`--margen`); cada sección abre con 72 a 128 px de aire arriba y el pie con 96 a 160 px. Cabecera fija de 56 px (52 en móvil) con la marca y el menú en etiquetas mono; por debajo de 720 px el menú se queda solo en GitHub. Cortes: 720 (móvil estrecho), 760 (llamadas del mapa, software en dos columnas; por debajo, la demo pasa a captura), 900 (cadena en fila, bloques en dos columnas; demo con el teléfono a la derecha, instalador en dos columnas de texto y caja, tablero en tres columnas) y 980 px (portada en dos columnas, caminos de hardware lado a lado, mapa del repositorio y compilar lado a lado).

- **Portada desde 980 px**: dos columnas (.82fr texto, 1.18fr mapa), alto de la pantalla menos la cabecera; a la izquierda titular, entrada, píldora y nota; a la derecha el mando y su tecla.
- **Portada por debajo de 980 px**: una sola columna en este orden: titular, entrada, nota (estado y licencia), ayuda del mapa, mando, píldora y tecla del control elegido. La frase dice qué es antes de pedir que se toque; la píldora queda pegada al mando y la tecla cierra la portada.
- **Tablero de estado**: rejilla de mínimo 260 px con 12 px de hueco (la única rejilla con hueco entre cajas: son teclas, como en la app); tres columnas desde 900 px.

La app de Mac usa un `HStack` con el índice de 220 px y no `NavigationSplitView`: su barra lateral es de cristal en los macOS recientes y nunca quedaría negra.

## Elevation & Depth

No hay. Sin sombras, sin degradados de superficie y sin escalera de tonos: una caja se separa con su línea. Lo que flota (toast, barra de edición) va sobre negro con línea fuerte. Los fondos encendidos (lima al 8 %) son planos, aunque en CSS se escriban como `linear-gradient` de un solo color.

**El latido no es sombra.** El anillo que se expande y se desvanece alrededor de un punto vivo (`box-shadow` animado a transparente) es movimiento, no profundidad: se permite y es parte del mundo. Lo que no se permite es una sombra en reposo.

## Shapes

Radio 0 en cajas, botones, campos, teclas e interruptores. Píldora solo en la acción principal. Círculos solo en puntos de estado (también el que viaja por el cable de la web) y en el dibujo del mando, que es físicamente redondo: sticks, botones, gatillos y PS siguen la silueta real del DualSense. Los marcadores del mapa son cuadrados, como todo lo que se toca. Bordes siempre de 1 px; la edición de teclas pasa a línea discontinua, y en el tablero de la web la discontinua marca lo que no hay («No»).

**El teléfono de la demo** es la otra excepción por la misma razón que el mando: es un objeto físico redondo. Marco de línea fuerte con 52 px de radio y pantalla con 42 px (40 y 30 px en móvil). Lo de dentro, la app, sigue con radio 0. No es licencia para redondear cajas.

## Motion

`cubic-bezier(.16,1,.3,1)` en casi todo. Los puntos vivos laten a 1,6 s, y lo que espera parpadea a 1,2 s. Cambiar de sección hace un `asoma` de 4 px. Los estados llegan 20 veces por segundo: `pintarSi` solo rehace el HTML si cambia, porque si no el latido se reiniciaría y no llegaría a verse. Con `prefers-reduced-motion` no se mueve nada, tampoco en la app de Mac. En la web: el punto del cable recorre la cadena en 3,6 s lineales (y desaparece con movimiento reducido); el marcador crece a 1,25 en hover; la píldora baja a .98 al pulsarla; las funciones de la tecla entran con `asoma` escalonado de 50 ms; el «+» del FAQ y el de la ayuda del instalador giran 45°; el salto elegido de la demo late como el marcador; la flecha de «Ajústalo en la demo» baja 2 px en hover.

## Components

- **Caja** (`.card`, `Tarjeta`): línea normal y cabecera de etiqueta con línea fina debajo; filas separadas por línea fina.
- **Botón** (`.btn`, `BotonCaja`): mono sobre blanco al 8 %, línea normal. **Fuerte**: píldora blanca. **Malo**: rojo sobre transparente. **Peligro**: rojo sólido con texto negro.
- **Tecla** (`.wbtn`, `WidgetBoton`): símbolo arriba a la izquierda, ON/OFF arriba a la derecha y nombre abajo. Encendida: línea, símbolo y estado en lima, fondo lima al 8 % y punto latiendo. La pausa, en rojo. El tipo lo dice el símbolo, no el color.
- **Estado** (`.chip`, `Punto`): punto de 6 px y mono de 12 px, sin caja.
- **Interruptor** (`.tog`, `Interruptor`): rectángulo de línea con un cuadrado dentro; encendido en lima.
- **Deslizador** (`input[type=range]`, `Raya`): raya de 2 px con tramo lima y pomo blanco rectangular. Los de dos sentidos se rellenan desde el cero. En la app de Mac es propio porque el nativo no admite raya fina ni relleno desde el cero; se maneja con las flechas y VoiceOver ve un `Slider`.
- **Índice** (`nav`, `Indice`): texto en filas; hover y sección activa en lima, con el icono desplazándose 3 px.
- **Toast y aviso**: negro con línea (roja si es error), mono de 12 px.

### Componentes de la web

- **Mapa del mando**: DualSense a línea en SVG (viewBox 640 × 400), cuerpo en blanco al 62 %, piezas en línea fuerte, símbolos en tenue, trazo que no escala. Encima, un marcador por control: cuadrado de 9 px solo de línea (blanco al 72 %) dentro de una zona táctil de 44 px. El elegido (R2 al empezar) se rellena de lima y late; su forma en el dibujo pasa a lima con fondo lima al 8 %. Encima, una etiqueta tenue: «Toca una parte del mando».
- **Llamadas de plano** (desde 760 px): de cada control sale una línea guía fina en ángulo recto hasta su nombre, en mono de 11 px en mayúsculas, **fuera de la silueta**; el mando deja 118 px a cada lado para ellas. El nombre también se puede tocar. La llamada del elegido, en lima. Por debajo de 760 px no hay llamadas: solo marcadores.
- **Tecla de funciones**: la misma anatomía de caja que la app: línea normal, cabecera con la etiqueta del control en lima y su resumen a la derecha, línea fina debajo; las funciones en columnas de 180 px como mínimo separadas por línea fina, cada una con un cuadradito de 6 px de línea, título de 16 px y texto de 14 px. Se anuncia con `aria-live`.
- **Etiqueta «Solo sin conexión»**: mono de 10,5 px en mayúsculas, blanco, con línea fuerte. Es blanca porque avisa sin ser un fallo; no se pone en rojo.
- **Aviso**: caja de línea fuerte a todo el ancho de la página, sin relleno, con la etiqueta arriba y título de 22 px.
- **Cadena del recorrido**: eslabones de caja de línea (DualSense → p5k-ps5 → P5Mate → PS5) unidos por un cable de línea fuerte, horizontal desde 900 px y vertical a la izquierda en móvil; un punto lima de 7 px viaja por él por detrás de los eslabones. Es el informe, es decir, el mecanismo, no un adorno. Solo el eslabón de la placa está vivo (línea y nombre en lima, fondo lima al 8 %).
- **Caminos de hardware**: dos cajas de línea que comparten borde; cabecera con nombre de 22 px y estado (punto lima que late: probado; punto blanco que parpadea: pendiente); render a sangre entre líneas finas; **ficha** en `dl` con `dt` de etiqueta y `dd` en mono 300 de 14 px.
- **Pasos numerados**: contador en mono 300 de 34 px a la izquierda (56 px de columna; 36 en móvil) y filas separadas por línea fina. Dentro, los ajustes en una caja de línea con filas `dt`/`dd` en mono de 13 px.
- **Pestañas**: fila de 48 px en mono de 12 px en mayúsculas sobre una línea; la elegida en lima con subrayado de 2 px.
- **Tabla**: cabeceras en etiqueta tenue, filas con línea fina, números y pines en mono 300 de 13 px.
- **Preguntas**: `details` en filas de 60 px de alto mínimo con línea fina; un «+» mono tenue que, al abrirse, gira 45° y pasa a lima.
- **Píldora**: blanca, 48 px de alto, Inter Tight 500 de 16 px. Una por sección como mucho: «Fabrícate uno» en la portada e «Instalar en la placa» en el instalador; los demás enlaces son texto o dato.
- **Píldora de línea**: la misma forma en negro con línea fuerte y texto blanco. Solo «Abrir la demo», sobre la captura del teléfono en móvil.
- **Teléfono con la demo**: la app de verdad (`web/demo/`, generada desde `app/Pagina.swift` por `herramientas/demo.py` con el simulador de `web/demo/simulador.js`) en un `iframe` de 390 × 780 px dentro de un marco de línea fuerte (radio 52/42 px). Por debajo de 760 px no se carga el `iframe`: una captura a todo el ancho (proporción 390/600, radio 40/30 px) con la píldora de línea abajo, que abre la demo. Debajo, un pie mono: punto lima «Demo» y «mando simulado · los cambios no se guardan».
- **Saltos de la demo**: lista junto al teléfono (desde 760 px) con botones a todo el ancho separados por línea fina: cuadrado de 9 px de línea como el marcador del mapa, nombre de 18 px y descripción de 14 px suave. Cada uno lleva el `iframe` a una pantalla; el elegido rellena el cuadrado de lima, late y pone el nombre en lima.
- **«Ajústalo en la demo»**: última fila de la tecla de funciones, de 48 px, en mono de 12 px en mayúsculas suave sobre línea fina, con una flecha «↓» tenue que pasa a lima en hover. Baja a la demo y abre la pantalla de ese control.
- **Caja del instalador**: la única caja con borde lima y fondo lima al 8 %. Cabecera como la tecla (etiqueta lima «Firmware» y estado a la derecha), ficha del firmware, píldora blanca, nota de 14 px tenue y, al final, un desplegable de ayuda de 48 px en mono de 12 px con el «+» que gira. Si el navegador no puede grabar, una caja de línea fuerte lo explica en palabras.
- **Mini pasos**: lista numerada a la izquierda en mono 300 de 20 px tenue, filas de línea fina y texto de 15 px suave con lo importante en blanco 500.
- **Tablero de estado**: piezas como teclas de la app, con el estado arriba a la derecha (etiqueta mono con punto de 6 px) y el nombre abajo. **Probado**: borde, fondo al 8 % y estado en lima, punto que late. **Hecho**: punto blanco fijo. **Por probar**: punto blanco que parpadea. **No**: línea discontinua y nombre suave, punto solo de línea. Siempre con la palabra.
- **Mapa del repositorio**: filas de línea fina con la carpeta en mono 400 de 14 px (columna de 200 px) y su descripción; la carpeta pasa a lima en hover. En móvil, una debajo de otra.
- **Bloque de código**: caja de línea normal con 16 × 18 px de relleno, mono 300 de 13 px a 1.7 y desplazamiento horizontal.
- **Pie de figura de render**: «Render 3D…» en mono 300 de 12 px tenue bajo una línea fina, para que no se confunda un render con una foto.
- **Créditos del pie**: una frase de 14 px suave con los enlaces en blanco.

En la app de Mac siguen siendo nativos, en oscuro, los desplegables, los menús, los selectores por segmentos, los botones de radio, el `Stepper` y el selector de color.

## Icono

Baldosa negra y un único símbolo en lima `#C8F04D`, en sRGB exacto. El símbolo es propio: un mando de frente cuyo arco inferior es también el puente, con cruceta y dos botones en negativo. Se lee a 16 px. `app/icono.swift` lo dibuja (con `movil`, a sangre y sin alfa para iOS); el mismo trazado, en rejilla de 24, es el logo de la web y del instalador. `herramientas/iconos.sh` regenera los de Tauri; `128x128@2x.png` va a sangre porque es también el `/icono.png` de la placa y del servidor de escritorio.

## Do's and Don'ts

### Do
- Mirar `~/Developer/cabina` antes de inventar un componente.
- Mantener 44 px en táctil aunque la letra sea pequeña.
- Acompañar todo color de estado con su palabra.
- Usar `Tema` en Swift y las variables CSS en la web, nunca colores sueltos.
- Respetar `prefers-reduced-motion`.
- En la web, usar la escala web solo en la web, y poner las llamadas del mapa fuera de la silueta del mando.
- En la portada móvil, poner titular, entrada y nota antes del mando, y la píldora pegada al mando, antes de la tecla.
- Marcar como «Render 3D» todo lo que no sea una foto.

### Don't
- No añadir otro acento ni volver al ámbar, al verde o al azul.
- No poner sombras en reposo, degradados de superficie ni radios en las cajas (el anillo del latido sí vale).
- No usar el lima en un botón de acción ni en su hover: esa es la píldora blanca (86 % en hover).
- No poner más de una píldora blanca llena por sección; lo secundario es píldora de línea, texto o dato.
- No extender el radio del teléfono a las cajas: solo vale para el marco y la pantalla del teléfono.
- No llevar a la app la escala de titulares de la web.
- No poner en rojo la etiqueta «Solo sin conexión»: el rojo es para lo que falla.
- No cargar fuentes de internet: la placa puede no tenerlo.
- No aumentar el recorte de fuentes sin mirar lo que pesa dentro del firmware.
