#!/bin/bash
# Regenera pruebas/procesador.json con el procesador de Swift de la app de Mac (app/Procesador.swift).
# La prueba de Rust (cargo test procesador) comprueba que el de Rust da exactamente la misma salida.
set -e
cd "$(dirname "$0")"
RAIZ=../../..
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos13.0 \
  $RAIZ/app/Modelo.swift $RAIZ/app/Procesador.swift $RAIZ/app/MonitorSenales.swift $RAIZ/app/MedidorControl.swift \
  generar.swift -o "$TMP/generar"
"$TMP/generar" procesador.json
