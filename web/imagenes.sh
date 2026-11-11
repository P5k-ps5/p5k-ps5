#!/bin/zsh
# Regenera las imágenes de la web a partir del diseño (placa/ y caja/). Se ejecuta desde la raíz del repo:
#   web/imagenes.sh
# Necesita KiCad en /Applications y Google Chrome (para la vista 3D de la caja).
set -e
cd "$(dirname "$0")/.."
KC=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP=$(mktemp -d)

# Placa: arriba, algo inclinada; abajo, plana (para que el QR se lea)
$KC pcb render placa/puente.kicad_pcb -o web/img/placa-arriba.png --side top --quality high \
  --width 2400 --height 1320 --perspective --rotate "-28,0,0" --zoom 1.05 --background transparent >/dev/null
$KC pcb render placa/puente.kicad_pcb -o web/img/placa-abajo.png --side bottom --quality high \
  --width 2400 --height 1320 --zoom 1.15 --background transparent >/dev/null

# Caja plana abierta, desde su visor 3D (piezas separadas)
"$CHROME" --headless=new --use-angle=swiftshader --enable-unsafe-swiftshader --window-size=1200,760 \
  --virtual-time-budget=9000 --user-data-dir="$TMP/perfil" --hide-scrollbars \
  --screenshot="$TMP/caja.png" "file://$PWD/caja/plana/visor.html#separar=0.75,limpio" >/dev/null 2>&1
sips -c 660 1200 --cropOffset 0 0 "$TMP/caja.png" --out web/img/caja.png >/dev/null

rm -rf "$TMP"
echo "Imágenes en web/img/"
