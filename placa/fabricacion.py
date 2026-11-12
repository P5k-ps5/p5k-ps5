"""Archivos de fabricación para JLCPCB, en placa/fabricacion/:

- puente-gerber.zip: Gerber y taladros (lo que se sube en «Añadir archivo Gerber»)
- puente-bom.csv:    lista de piezas en el formato de JLCPCB (Comment, Designator, Footprint, LCSC Part #)
- puente-cpl.csv:    posición y giro de cada pieza (Designator, Mid X, Mid Y, Layer, Rotation)

Uso (desde la raíz del repo): python3 placa/fabricacion.py
Las piezas sin montar (conectores de pantalla y puntos de prueba) no van ni en la BOM ni en la CPL.
"""
import csv
import subprocess
import tempfile
import zipfile
from collections import defaultdict
from pathlib import Path

from diseno import COMPONENTES

KC = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"
AQUI = Path(__file__).parent
PLACA = AQUI / "puente.kicad_pcb"
SALIDA = AQUI / "fabricacion"
CAPAS = "F.Cu,B.Cu,F.Paste,B.Paste,F.Silkscreen,B.Silkscreen,F.Mask,B.Mask,Edge.Cuts"


def cli(*args):
    subprocess.run([KC, *args], check=True, capture_output=True)


def main():
    SALIDA.mkdir(exist_ok=True)
    montadas = [c for c in COMPONENTES if not c.get("dnp")]

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        cli("pcb", "export", "gerbers", str(PLACA), "-o", str(tmp), "--layers", CAPAS, "--subtract-soldermask")
        cli("pcb", "export", "drill", str(PLACA), "-o", str(tmp) + "/", "--format", "excellon",
            "--excellon-units", "mm", "--generate-map", "--map-format", "gerberx2")
        with zipfile.ZipFile(SALIDA / "puente-gerber.zip", "w", zipfile.ZIP_DEFLATED) as z:
            for f in sorted(tmp.iterdir()):
                z.write(f, f.name)
        nombres = sorted(f.name for f in tmp.iterdir())

        # CPL: KiCad da la posición desde el origen de la hoja; JLCPCB solo necesita las posiciones relativas
        cli("pcb", "export", "pos", str(PLACA), "-o", str(tmp / "pos.csv"), "--format", "csv", "--units", "mm",
            "--side", "front", "--exclude-dnp")
        filas = list(csv.DictReader((tmp / "pos.csv").open()))
    validas = {c["ref"] for c in montadas}
    # Correcciones para los modelos de JLCPCB, comprobadas en su visor de montaje (12 nov. 2026): su ESP32-S3-WROOM-1
    # tiene el origen más abajo que la huella de KiCad, y su MAX3421E en TQFN y su 1N4148W vienen girados.
    # (desplazamiento x e y en mm sobre la placa, con y hacia abajo como en KiCad; giro en grados, antihorario)
    CORRECCIONES = {"U1": (0.0, 3.4, 0), "U2": (0.0, 0.0, -90), "D2": (0.0, 0.0, 180)}
    with (SALIDA / "puente-cpl.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Designator", "Mid X", "Mid Y", "Layer", "Rotation"])
        for r in sorted(filas, key=lambda r: r["Ref"]):
            if r["Ref"] in validas:
                dx, dy, giro = CORRECCIONES.get(r["Ref"], (0.0, 0.0, 0))
                # KiCad exporta la y hacia arriba (negativa): bajar en la placa es restar
                w.writerow([r["Ref"], f'{float(r["PosX"]) + dx:.3f}mm', f'{float(r["PosY"]) - dy:.3f}mm', "Top",
                            f'{(float(r["Rot"]) + giro) % 360:.0f}'])

    # BOM agrupada por pieza
    grupos = defaultdict(list)
    for c in montadas:
        # Una línea por pieza (número LCSC): JLCPCB rechaza dos líneas con la misma pieza aunque se llamen
        # distinto (J1 «CONSOLA» y J2 «MANDO»)
        grupos[(c["fp"].split(":")[1], c["lcsc"])].append(c)
    clave = lambda ref: (ref.rstrip("0123456789"), int(ref[len(ref.rstrip("0123456789")):] or 0))
    with (SALIDA / "puente-bom.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Comment", "Designator", "Footprint", "LCSC Part #"])
        for (fp, lcsc), comps in sorted(grupos.items(), key=lambda g: clave(sorted((c["ref"] for c in g[1]), key=clave)[0])):
            valor = "/".join(dict.fromkeys(c["valor"] for c in sorted(comps, key=lambda c: clave(c["ref"]))))
            w.writerow([valor, ",".join(sorted((c["ref"] for c in comps), key=clave)), fp, lcsc])

    print(f"{len(nombres)} archivos en el zip de Gerber; {len(montadas)} piezas montadas en {len(grupos)} referencias")
    print("En", SALIDA)


if __name__ == "__main__":
    main()
