#!/bin/bash
# Genera los iconos de la app de escritorio a partir de app/icono.swift (la app de Mac los saca en construir_app.sh).
# 128x128@2x.png va a sangre porque también es el /icono.png que sirven la placa y el servidor de escritorio al
# móvil, y entra en el firmware: cambiarlo no cambia nada más que la imagen.
set -e
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
swiftc app/icono.swift -o "$TMP/icono" -framework Cocoa
"$TMP/icono" "$TMP/icono.png"
"$TMP/icono" "$TMP/icono-movil.png" movil
(cd escritorio && npx --no-install tauri icon "$TMP/icono.png" -o "$TMP/salida" >/dev/null)
D=escritorio/src-tauri/icons
cp "$TMP"/salida/{32x32.png,128x128.png,icon.icns,icon.ico,icon.png} "$D/"
sips -z 256 256 "$TMP/icono-movil.png" --out "$D/128x128@2x.png" >/dev/null
rm -rf "$TMP"
echo "Iconos listos en $D"
