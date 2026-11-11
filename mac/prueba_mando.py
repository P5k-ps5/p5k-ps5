#!/usr/bin/env python3
"""Prueba de la fase 1: el Mac ve el ESP32 como mando de PS4 y responde a las órdenes.

Necesita la placa conectada al Mac por el USB-C "USB" (nativo) y en modo mac.
Requisitos: pip install hidapi pyserial
"""
import glob
import sys
import time

import hid
import serial

VID, PID = 0x054C, 0x09CC


def buscar_serie():
    # El COM (chip CH343) sale como usbmodem5CE5...; el puerto del ESP32 es el otro
    for puerto in sorted(glob.glob("/dev/cu.usbmodem*")):
        if "5CE52173911" not in puerto:
            return puerto
    return None


def leer_informe(mando, intentos=50):
    for _ in range(intentos):
        datos = mando.read(64, 20)
        if datos and datos[0] == 0x01:
            return datos
    return None


def resumen(d):
    return (f"stick izq ({d[1]:3},{d[2]:3})  stick der ({d[3]:3},{d[4]:3})  "
            f"cruceta {d[5] & 0x0F}  botones {d[5] >> 4:04b} {d[6]:08b} {d[7] & 3:02b}  "
            f"L2 {d[8]:3} R2 {d[9]:3}")


def main():
    if not any(d["vendor_id"] == VID and d["product_id"] == PID for d in hid.enumerate()):
        sys.exit("El Mac no ve ningún mando de PS4. ¿Está la placa en el USB-C 'USB'?")
    mando = hid.device()
    mando.open(VID, PID)
    print(f"Mando encontrado: {mando.get_manufacturer_string()} / {mando.get_product_string()}")

    puerto = buscar_serie()
    if not puerto:
        sys.exit("No encuentro el puerto serie del ESP32 (¿está en modo consola?)")
    esp = serial.Serial(puerto, 115200, timeout=0.3)
    print(f"Puerto serie: {puerto}\n")

    def orden(texto, esperar=0.15):
        esp.write((texto + "\n").encode())
        time.sleep(esperar)
        respuesta = esp.read(4096).decode(errors="replace").strip()
        informe = leer_informe(mando)
        print(f"> {texto:28} {respuesta[:40]:40}")
        print(f"  {resumen(informe) if informe else 'sin informe'}")
        return informe

    reposo = orden("suelta")
    x = orden("manten x")
    orden("suelta x")
    orden("stick izq 100 0")
    orden("stick der 0 100")
    orden("gatillo r2 50")
    orden("pulsa arriba 1000")
    orden("suelta")

    ok = reposo and x and reposo[1] == 128 and (x[5] >> 4) & 0b0010
    print("\nResultado:", "el Mac recibe el mando del ESP32 ✔" if ok else "algo no cuadra ✘")
    orden("estado", 0.4)


if __name__ == "__main__":
    main()
