"""Genera qr.json (la matriz del QR de la web) para que pcb.py la dibuje en la serigrafía de la cara de abajo.

Necesita segno (pip install segno); pcb.py corre con el Python de KiCad, que no lo trae: por eso va en un JSON.
"""
import json
from pathlib import Path

import segno

URL = "https://p5k-ps5.github.io"

if __name__ == "__main__":
    q = segno.make(URL, error="m", micro=False)
    filas = ["".join("1" if m else "0" for m in fila) for fila in q.matrix]
    destino = Path(__file__).parent / "qr.json"
    destino.write_text(json.dumps({"url": URL, "version": q.version, "filas": filas}, indent=1) + "\n")
    print(f"QR versión {q.version} ({len(filas)}x{len(filas)}):", destino)
