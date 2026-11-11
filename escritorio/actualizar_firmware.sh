#!/bin/bash
# Copia el firmware compilado con ESP-IDF (idf.py build) a la app de escritorio.
set -e
cd "$(dirname "$0")/.."
DEST=escritorio/src-tauri/firmware
# El firmware de la placa sin ordenador (WiFi, motor, OTA) usa otra tabla de particiones: la app va en
# 0x20000 y hay que grabar también otadata en 0xf000 (ver partitions.csv). src-tauri/src/placa.rs todavía
# graba con la tabla antigua (app en 0x10000): copiar este firmware sin cambiar placa.rs dejaría la placa
# sin arrancar.
if [ -f build/ota_data_initial.bin ] && ! grep -q "0x20000" escritorio/src-tauri/src/placa.rs; then
  echo "Este firmware usa la tabla de particiones nueva (OTA): actualiza antes las direcciones de"
  echo "escritorio/src-tauri/src/placa.rs (otadata en 0xf000 y la app en 0x20000) y copia también"
  echo "build/ota_data_initial.bin. No se ha copiado nada."
  exit 1
fi
for f in build/bootloader/bootloader.bin build/partition_table/partition-table.bin build/puente_mando.bin; do
  [ -f "$f" ] || { echo "Falta $f: ejecuta antes 'idf.py build'"; exit 1; }
done
cp build/bootloader/bootloader.bin "$DEST/bootloader.bin"
cp build/partition_table/partition-table.bin "$DEST/particiones.bin"
cp build/puente_mando.bin "$DEST/puente_mando.bin"
echo "Firmware copiado a $DEST. Las direcciones (0x0, 0x8000, 0x10000) están en src-tauri/src/placa.rs."
