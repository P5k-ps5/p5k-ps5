#!/bin/bash
# Compila y ejecuta las pruebas del motor (sin Xcode). Uso: ./ejecutar_pruebas.sh
# Necesitan macOS (el almacén de perfiles y el procesador usan Foundation de macOS).
set -e
cd "$(dirname "$0")"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if [ "$(uname)" != "Darwin" ]; then
  echo "Las pruebas del motor necesitan macOS."
  exit 0
fi
echo "== Pruebas del motor"
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos13.0 \
  app/Modelo.swift app/Procesador.swift app/Sincro.swift app/MonitorSenales.swift app/MedidorControl.swift \
  pruebas/Escenario.swift pruebas/pruebas.swift -o "$TMP/pruebas"
"$TMP/pruebas" pruebas/huella_ayuda.json
