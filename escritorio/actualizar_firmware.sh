#!/bin/bash
# Copia el firmware compilado con ESP-IDF (idf.py build) a la app de escritorio.
set -e
cd "$(dirname "$0")/.."
DEST=escritorio/src-tauri/firmware
# El firmware usa la tabla de particiones con OTA (partitions.csv): la app va en 0x20000 y se graba también
# otadata en 0xf000. src-tauri/src/placa.rs tiene que grabar con esas direcciones: con las antiguas (app en
# 0x10000) la placa no arrancaría.
if ! grep -q "0x20000" escritorio/src-tauri/src/placa.rs; then
  echo "Este firmware usa la tabla de particiones nueva (OTA): actualiza antes las direcciones de"
  echo "escritorio/src-tauri/src/placa.rs (otadata en 0xf000 y la app en 0x20000) y copia también"
  echo "build/ota_data_initial.bin. No se ha copiado nada."
  exit 1
fi
for f in build/bootloader/bootloader.bin build/partition_table/partition-table.bin build/ota_data_initial.bin build/puente_mando.bin; do
  [ -f "$f" ] || { echo "Falta $f: ejecuta antes 'idf.py build'"; exit 1; }
done
cp build/bootloader/bootloader.bin "$DEST/bootloader.bin"
cp build/partition_table/partition-table.bin "$DEST/particiones.bin"
cp build/ota_data_initial.bin "$DEST/ota_data_initial.bin"
cp build/puente_mando.bin "$DEST/puente_mando.bin"
cat > "$DEST/firmware.json" <<JSON
{
  "version": "$(date +%Y.%m.%d)",
  "chip": "esp32s3",
  "piezas": [
    { "archivo": "bootloader.bin", "direccion": "0x0" },
    { "archivo": "particiones.bin", "direccion": "0x8000" },
    { "archivo": "ota_data_initial.bin", "direccion": "0xf000" },
    { "archivo": "puente_mando.bin", "direccion": "0x20000" }
  ]
}
JSON
echo "Firmware copiado a $DEST. Las direcciones (0x0, 0x8000, 0xf000, 0x20000) están en src-tauri/src/placa.rs."
