#!/bin/bash
# Compila "p5k-ps5.app" en esta carpeta (no hace falta Xcode).
set -e
cd "$(dirname "$0")"
APP="p5k-ps5.app"
TMP=$(mktemp -d)
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos13.0 $SWIFTFLAGS app/Modelo.swift app/Procesador.swift app/Sincro.swift app/Motor.swift app/Servidor.swift app/MonitorSenales.swift app/MedidorControl.swift app/Pagina.swift app/Vistas.swift \
  -o "$APP/Contents/MacOS/PuenteDeMando" -framework SwiftUI -framework GameController
# icono
swiftc app/icono.swift -o "$TMP/icono" -framework Cocoa
"$TMP/icono" "$TMP/icono.png"
mkdir "$TMP/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icono.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icono.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
# icono para el acceso directo del móvil (180 px, el que pide iOS): a sangre y sin transparencia
"$TMP/icono" "$TMP/icono-movil.png" movil
sips -z 180 180 "$TMP/icono-movil.png" --out "$APP/Contents/Resources/icono-movil.png" >/dev/null
# fuentes de la interfaz (ATSApplicationFontsPath las carga al abrir la app)
mkdir "$APP/Contents/Resources/fuentes"
cp app/fuentes/*.ttf "$APP/Contents/Resources/fuentes/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>p5k-ps5</string>
  <key>CFBundleDisplayName</key><string>p5k-ps5</string>
  <key>CFBundleIdentifier</key><string>com.neuroaigency.puentedemando</string>
  <key>CFBundleExecutable</key><string>PuenteDeMando</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>ATSApplicationFontsPath</key><string>fuentes</string>
  <key>GCSupportsControllerUserInteraction</key><true/>
  <key>GCSupportedGameControllers</key><array><dict><key>ProfileName</key><string>ExtendedGamepad</string></dict></array>
</dict></plist>
PLIST
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
rm -rf "$TMP"
echo "Listo: $(pwd)/$APP"
