"""Mete en la placa las pistas que ha trazado Freerouting (puente.ses), rellena los planos de masa y guarda.

Flujo completo (desde placa/), con el Python de KiCad ($PY) y Java:
    $PY pcb.py                       # placa sin pistas: contorno, componentes, planos
    $PY importar_rutas.py dsn        # exporta puente.dsn para Freerouting
    java -jar freerouting-2.5.0.jar -de puente.dsn -do puente.ses -mp 30 --gui.enabled=false
    $PY importar_rutas.py ses        # importa puente.ses, rellena planos y guarda
"""
import sys
from pathlib import Path

import pcbnew

AQUI = Path(__file__).parent
PLACA = AQUI / "puente.kicad_pcb"

def coser_masa(board):
    """Vías de masa entre los planos de arriba y de abajo: una en cada isla del plano de arriba (trozos que las
    pistas dejan sueltos) y una rejilla cada 4 mm. Solo donde caben enteras en los dos planos y fuera de las
    zonas sin vías (el QR)."""
    gnd = board.FindNet("/GND")
    zonas = {z.GetLayer(): z for z in board.Zones() if not z.GetIsRuleArea()}
    sin_vias = [z for z in board.Zones() if z.GetIsRuleArea() and z.GetDoNotAllowVias()]
    margen = pcbnew.FromMM(0.42)          # radio de la vía (0,3) + algo: la vía queda dentro del cobre de masa
    planos = {}
    for capa in (pcbnew.F_Cu, pcbnew.B_Cu):
        poli = zonas[capa].GetFilledPolysList(capa).CloneDropTriangulation()
        poli.Deflate(margen, pcbnew.CORNER_STRATEGY_ROUND_ALL_CORNERS, pcbnew.FromMM(0.01))
        planos[capa] = poli
    vias = [t.GetPosition() for t in board.GetTracks() if t.GetClass() == "PCB_VIA"]
    # Todos los taladros (vías y pads pasantes), con su radio, para no acercarse a menos de 0,25 mm
    taladros = [(t.GetPosition(), t.GetDrillValue() / 2) for t in board.GetTracks() if t.GetClass() == "PCB_VIA"]
    for fp in board.GetFootprints():
        for pad in fp.Pads():
            if pad.HasHole():
                taladros.append((pad.GetPosition(), max(pad.GetDrillSize().x, pad.GetDrillSize().y) / 2))
    radio = pcbnew.FromMM(0.15)                  # taladro de la vía nueva (0,3 mm)
    separacion = pcbnew.FromMM(0.3)              # mínimo de JLCPCB entre taladros (0,25) con margen
    r_via = pcbnew.FromMM(0.35)

    def fuera_de_sin_vias(p):
        return not any(z.Outline().Contains(pcbnew.VECTOR2I(p.x + dx, p.y + dy))
                       for z in sin_vias for dx, dy in ((0, 0), (r_via, 0), (-r_via, 0), (0, r_via), (0, -r_via)))

    def lejos_de_taladros(p):
        return all((p.x - q.x) ** 2 + (p.y - q.y) ** 2 >= (r + radio + separacion) ** 2 for q, r in taladros)

    def cabe(p):
        return (planos[pcbnew.F_Cu].Contains(p) and planos[pcbnew.B_Cu].Contains(p)
                and fuera_de_sin_vias(p) and lejos_de_taladros(p))

    def poner(p):
        v = pcbnew.PCB_VIA(board)
        v.SetPosition(p)
        v.SetWidth(pcbnew.FromMM(0.6))
        v.SetDrill(pcbnew.FromMM(0.3))
        v.SetNet(gnd)
        board.Add(v)
        vias.append(p)
        taladros.append((p, radio))

    lejos = lambda p, d: all((p.x - q.x) ** 2 + (p.y - q.y) ** 2 > d * d for q in vias)
    paso = pcbnew.FromMM(0.25)
    puestas = 0
    # Una por isla del plano de arriba
    arriba = zonas[pcbnew.F_Cu].GetFilledPolysList(pcbnew.F_Cu)
    for i in range(arriba.OutlineCount()):
        caja = arriba.Outline(i).BBox()
        cx, cy = caja.GetCenter().x, caja.GetCenter().y
        puntos = [pcbnew.VECTOR2I(x, y) for x in range(caja.GetLeft(), caja.GetRight(), paso)
                  for y in range(caja.GetTop(), caja.GetBottom(), paso)]
        puntos.sort(key=lambda p: (p.x - cx) ** 2 + (p.y - cy) ** 2)
        for p in puntos:
            if arriba.Outline(i).PointInside(p) and cabe(p):
                if lejos(p, pcbnew.FromMM(1.0)):
                    poner(p)
                    puestas += 1
                break
        else:
            print(f"  isla sin sitio para una vía: {pcbnew.ToMM(caja.GetLeft()) - 100:.1f},{pcbnew.ToMM(caja.GetTop()) - 100:.1f} "
                  f"({pcbnew.ToMM(caja.GetWidth()):.1f} x {pcbnew.ToMM(caja.GetHeight()):.1f} mm)")
    # Rejilla cada 4 mm
    borde = board.GetBoardEdgesBoundingBox()
    rejilla = pcbnew.FromMM(4.0)
    for x in range(borde.GetLeft() + rejilla // 2, borde.GetRight(), rejilla):
        for y in range(borde.GetTop() + rejilla // 2, borde.GetBottom(), rejilla):
            p = pcbnew.VECTOR2I(x, y)
            if cabe(p) and lejos(p, pcbnew.FromMM(2.0)):
                poner(p)
                puestas += 1
    return puestas


def ensanchar_alimentacion():
    """VBUS y VBUS_MANDO llevan la carga del DualSense: se trazan a 0,3 mm (entre los pads del USB-C no cabe más) y
    aquí se ensanchan a 0,6 mm. El DRC de KiCad dice qué tramos chocan con algo, y esos bajan a 0,4 y luego a 0,3."""
    import json
    import subprocess
    kc = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"
    redes = {"/VBUS", "/VBUS_MANDO"}
    for ancho in (0.6, 0.4, 0.3):   # el último paso solo estrecha a 0,2 lo que sigue chocando (llegadas a pads finos)
        board = pcbnew.LoadBoard(str(PLACA))
        for t in board.GetTracks():
            if ancho > 0.3 and t.GetClass() == "PCB_TRACK" and t.GetNetname() in redes and t.GetWidth() < pcbnew.FromMM(ancho):
                t.SetWidth(pcbnew.FromMM(ancho))
        pcbnew.ZONE_FILLER(board).Fill(board.Zones())
        board.Save(str(PLACA))
        for _ in range(6):
            informe = AQUI / "drc.json"
            subprocess.run([kc, "pcb", "drc", "--format", "json", "-o", str(informe), str(PLACA)], capture_output=True)
            datos = json.loads(informe.read_text())
            informe.unlink()
            malos = {it["uuid"] for v in datos.get("violations", []) for it in v.get("items", [])
                     if v["type"] in ("clearance", "hole_clearance", "copper_edge_clearance", "shorting_items")}
            board = pcbnew.LoadBoard(str(PLACA))
            atras = [t for t in board.GetTracks() if t.GetClass() == "PCB_TRACK" and t.GetNetname() in redes
                     and t.m_Uuid.AsString() in malos and t.GetWidth() > pcbnew.FromMM(0.3 if ancho > 0.3 else 0.2)]
            if not atras:
                break
            for t in atras:   # vuelve al ancho anterior de este paso
                t.SetWidth(pcbnew.FromMM({0.6: 0.4, 0.4: 0.3, 0.3: 0.2}[ancho]))
            pcbnew.ZONE_FILLER(board).Fill(board.Zones())
            board.Save(str(PLACA))
    board = pcbnew.LoadBoard(str(PLACA))
    anchos = {}
    for t in board.GetTracks():
        if t.GetClass() == "PCB_TRACK" and t.GetNetname() in redes:
            w = round(pcbnew.ToMM(t.GetWidth()), 2)
            anchos[w] = anchos.get(w, 0) + pcbnew.ToMM(t.GetLength())
    print("VBUS y VBUS_MANDO (mm de pista por ancho):", {k: round(v, 1) for k, v in sorted(anchos.items())})


if __name__ == "__main__":
    board = pcbnew.LoadBoard(str(PLACA))
    if sys.argv[1] == "dsn":
        # Sin los planos de masa: así Freerouting traza también la masa con pistas (no la deja al plano) y
        # ninguna patilla de masa depende de que el relleno llegue hasta ella. Los planos se rellenan después.
        for z in list(board.Zones()):
            if not z.GetIsRuleArea():
                board.Remove(z)
        assert pcbnew.ExportSpecctraDSN(board, str(AQUI / "puente.dsn"))
        print("Exportado puente.dsn")
    else:
        assert pcbnew.ImportSpecctraSES(board, str(AQUI / "puente.ses")), "no se pudo importar puente.ses"
        # Freerouting estrecha algún tramo al entrar en un pad por debajo del mínimo: al mínimo
        minimo = pcbnew.FromMM(0.15)
        for t in board.GetTracks():
            if t.GetClass() == "PCB_TRACK" and t.GetWidth() < minimo:
                t.SetWidth(minimo)
        pcbnew.ZONE_FILLER(board).Fill(board.Zones())
        n = coser_masa(board)
        pcbnew.ZONE_FILLER(board).Fill(board.Zones())
        print(f"Cosido de masa: {n} vías")
        board.Save(str(PLACA))
        ensanchar_alimentacion()
        board = pcbnew.LoadBoard(str(PLACA))
        pistas = [t for t in board.GetTracks() if t.GetClass() == "PCB_TRACK"]
        vias = [t for t in board.GetTracks() if t.GetClass() == "PCB_VIA"]
        print(f"Importadas {len(pistas)} pistas y {len(vias)} vías; planos rellenos")
