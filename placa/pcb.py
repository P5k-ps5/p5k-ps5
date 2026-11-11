"""Genera la placa (puente.kicad_pcb) a partir de diseno.py: contorno, colocación y planos de masa.

Se ejecuta con el Python de KiCad (trae el módulo pcbnew):
    /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3.9 pcb.py

Coordenadas en mm desde la esquina de arriba a la izquierda de la placa; y hacia abajo (como en KiCad).
La antena del módulo sale por el borde de arriba (nada de cobre debajo).
"""
from pathlib import Path

import pcbnew

from diseno import COMPONENTES
from esquema import pines, simbolo

# Nombre de cada patilla en su símbolo (para nombrar igual que el esquema las redes de las patillas libres)
NOMBRES_PINES = {c["sym"]: {num: nombre for num, nombre, *_ in pines(simbolo(c["sym"]))} for c in COMPONENTES}

FOOTPRINTS = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints"
ANCHO, ALTO = 62.0, 30.0
ORIGEN = (100.0, 100.0)     # dónde cae la esquina de la placa en la hoja de KiCad

# (x, y, giro en grados). USB-C: a 270 la boca mira a la izquierda, a 90 a la derecha
POSICION = {
    # ESP32-S3: la primera fila de patillas a 1 mm del borde de arriba; la antena sobresale por arriba
    "U1": (31.0, 6.3, 0),
    # Lado izquierdo: USB-C de la consola, protección, alimentación, botones, LED
    "J1": (4.0, 9.0, 270),
    "U4": (13.4, 7.5, 0),
    "R13": (9.9, 6.3, 90), "R14": (9.9, 12.3, 90),
    "R1": (19.6, 1.3, 0), "C4": (19.6, 2.5, 0), "C3": (19.6, 3.7, 0), "R2": (19.6, 4.9, 0),
    "C14": (19.6, 6.4, 0),
    "D1": (15.5, 11.5, 0), "C5": (17.9, 11.5, 90), "D2": (15.5, 14.2, 0),
    # Condensadores del regulador pegados a sus patillas: C1 a la entrada (abajo a la izquierda), C2 a la salida
    "C1": (9.6, 26.6, 90), "C15": (12.6, 18.0, 0), "C2": (20.4, 24.5, 90),
    "U3": (15.0, 24.5, 0),
    "SW2": (4.8, 19.5, 0), "SW1": (4.8, 26.3, 0),
    # Lado derecho: interruptor del VBUS del mando, MAX3421E con su cristal, USB-C del mando
    "Q1": (43.4, 2.6, 0), "Q2": (43.4, 6.4, 0),
    "R9": (46.4, 1.3, 0), "C13": (46.4, 2.5, 0), "R10": (46.4, 3.7, 0), "R11": (46.4, 4.9, 0),
    "R12": (46.4, 6.1, 0),
    # Cristal pegado a XI/XO (esquina de arriba a la derecha del MAX), con sus condensadores encima
    "Y1": (49.7, 7.2, 0), "C10": (48.7, 4.5, 0), "C11": (50.7, 4.5, 0),
    "C7": (51.95, 11.2, 90), "C9": (51.95, 13.7, 90), "C6": (41.7, 13.55, 90),
    "U2": (47.0, 13.5, 0),
    "C8": (41.7, 11.5, 90),
    "R3": (44.5, 19.3, 0), "R4": (49.5, 19.3, 0), "R15": (47.0, 19.3, 0),
    "J2": (58.0, 9.0, 90),
    "R5": (53.6, 16.0, 0), "R6": (53.6, 17.2, 0), "R7": (56.6, 16.0, 0), "R8": (56.6, 17.2, 0),
    "C12": (59.8, 16.6, 90),
    # Abajo: conectores de pantalla (sin montar) y puntos de prueba
    "J4": (23.5, 28.0, 90), "J3": (43.0, 28.0, 90),
    "TP1": (55.4, 21.0, 0), "TP2": (57.8, 21.0, 0), "TP3": (60.2, 21.0, 0),
    "TP4": (55.4, 23.5, 0), "TP5": (57.8, 23.5, 0), "TP6": (60.2, 23.5, 0),
}


def _p(x, y):
    return pcbnew.VECTOR2I(pcbnew.FromMM(ORIGEN[0] + x), pcbnew.FromMM(ORIGEN[1] + y))


def _contorno(board):
    r = 1.0
    puntos = [(r, 0), (ANCHO - r, 0), (ANCHO, r), (ANCHO, ALTO - r), (ANCHO - r, ALTO), (r, ALTO), (0, ALTO - r), (0, r)]
    rectas = [(0, 1), (2, 3), (4, 5), (6, 7)]
    for a, b in rectas:
        s = pcbnew.PCB_SHAPE(board)
        s.SetShape(pcbnew.SHAPE_T_SEGMENT)
        s.SetStart(_p(*puntos[a]))
        s.SetEnd(_p(*puntos[b]))
        s.SetLayer(pcbnew.Edge_Cuts)
        s.SetWidth(pcbnew.FromMM(0.1))
        board.Add(s)
    for cx, cy, a, b in ((ANCHO - r, r, 1, 2), (ANCHO - r, ALTO - r, 3, 4), (r, ALTO - r, 5, 6), (r, r, 7, 0)):
        s = pcbnew.PCB_SHAPE(board)
        s.SetShape(pcbnew.SHAPE_T_ARC)
        s.SetCenter(_p(cx, cy))
        s.SetStart(_p(*puntos[a]))
        s.SetArcAngleAndEnd(pcbnew.EDA_ANGLE(90, pcbnew.DEGREES_T), True)
        s.SetLayer(pcbnew.Edge_Cuts)
        s.SetWidth(pcbnew.FromMM(0.1))
        board.Add(s)


def _plano_masa(board, capa, red):
    z = pcbnew.ZONE(board)
    z.SetLayer(capa)
    z.SetNet(red)
    z.SetIsRuleArea(False)
    z.SetLocalClearance(pcbnew.FromMM(0.25))
    z.SetMinThickness(pcbnew.FromMM(0.2))
    z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)   # trozos sin conexión: fuera
    z.SetPadConnection(pcbnew.ZONE_CONNECTION_FULL)   # macizo: se suelda a máquina, y sin radios que se queden cortos
    z.SetThermalReliefGap(pcbnew.FromMM(0.3))
    z.SetThermalReliefSpokeWidth(pcbnew.FromMM(0.4))
    contorno = z.Outline()
    contorno.NewOutline()
    for x, y in ((0, 0), (ANCHO, 0), (ANCHO, ALTO), (0, ALTO)):
        contorno.Append(pcbnew.FromMM(ORIGEN[0] + x), pcbnew.FromMM(ORIGEN[1] + y))
    board.Add(z)


# Serigrafía: sin referencias (R13, C4...: no caben y no hacen falta para el montaje), solo textos útiles
TEXTOS = [  # (texto, x, y, alto, giro)
    ("CONSOLA", 4.0, 2.2, 1.0, 0), ("MANDO", 58.0, 2.2, 1.0, 0),
    ("RST", 4.8, 15.6, 0.8, 0), ("BOOT", 4.8, 22.95, 0.8, 0),
    ("p5k-ps5", 31.0, 21.3, 1.2, 0),
    ("GND 3V3 SCL SDA", 46.4, 25.3, 0.8, 0),
    ("PANTALLA SPI", 31.1, 22.9, 0.8, 0),
    ("TX  RX GND", 57.8, 19.3, 0.8, 0), ("3V3 BOOT EN", 57.8, 25.3, 0.8, 0),
]


def _serigrafia(board):
    for fp in board.GetFootprints():
        fp.Reference().SetVisible(False)
    for texto, x, y, alto, giro in TEXTOS:
        t = pcbnew.PCB_TEXT(board)
        t.SetText(texto)
        t.SetPosition(_p(x, y))
        t.SetLayer(pcbnew.F_SilkS)
        t.SetTextSize(pcbnew.VECTOR2I(pcbnew.FromMM(alto), pcbnew.FromMM(alto)))
        t.SetTextThickness(pcbnew.FromMM(alto * 0.15))
        t.SetTextAngleDegrees(giro)
        board.Add(t)


# QR de la web en la cara de abajo (vacía: todos los componentes van arriba). La tinta blanca rellena los módulos
# claros y el margen, y los oscuros quedan del color de la placa: así se lee como un QR normal (oscuro sobre
# claro) con cualquier cámara. Visto desde abajo: se dibuja en espejo para que no salga invertido.
QR_CENTRO = (15.5, 14.0)
QR_MODULO = 0.5          # mm por módulo: la serigrafía de JLCPCB lo imprime nítido
QR_MARGEN = 2            # módulos de margen claro alrededor


def _qr(board):
    import json
    datos = json.loads((Path(__file__).parent / "qr.json").read_text())
    filas = [[c == "1" for c in f] for f in datos["filas"]]
    n = len(filas) + 2 * QR_MARGEN
    claro = [[True] * n for _ in range(n)]
    for i, f in enumerate(filas):
        for j, oscuro in enumerate(f):
            claro[i + QR_MARGEN][j + QR_MARGEN] = not oscuro
    lado = n * QR_MODULO
    x0, y0 = QR_CENTRO[0] - lado / 2, QR_CENTRO[1] - lado / 2
    for i in range(n):
        j = 0
        while j < n:                       # tramos horizontales de módulos claros: un rectángulo cada uno
            if not claro[i][j]:
                j += 1
                continue
            k = j
            while k < n and claro[i][k]:
                k += 1
            # espejo: la columna j queda en x = x0 + (n - k) * módulo
            r = pcbnew.PCB_SHAPE(board)
            r.SetShape(pcbnew.SHAPE_T_RECT)
            r.SetStart(_p(x0 + (n - k) * QR_MODULO, y0 + i * QR_MODULO))
            r.SetEnd(_p(x0 + (n - j) * QR_MODULO, y0 + (i + 1) * QR_MODULO))
            r.SetFilled(True)
            r.SetWidth(0)
            r.SetLayer(pcbnew.B_SilkS)
            board.Add(r)
            j = k
    # Sin vías debajo del QR (sus taladros se comerían módulos); las pistas sí pueden pasar
    z = pcbnew.ZONE(board)
    z.SetIsRuleArea(True)
    z.SetDoNotAllowVias(True)
    z.SetDoNotAllowTracks(False)
    z.SetDoNotAllowPads(False)
    z.SetDoNotAllowZoneFills(False)
    z.SetDoNotAllowFootprints(False)
    z.SetLayerSet(pcbnew.LSET.AllCuMask())
    z.SetZoneName("QR: sin vías")
    contorno = z.Outline()
    contorno.NewOutline()
    for x, y in ((x0, y0), (x0 + lado, y0), (x0 + lado, y0 + lado), (x0, y0 + lado)):
        contorno.Append(pcbnew.FromMM(ORIGEN[0] + x), pcbnew.FromMM(ORIGEN[1] + y))
    board.Add(z)
    for texto, dy, alto in ((datos["url"].replace("https://", ""), lado / 2 + 1.6, 1.0),
                            ("GPL-3.0 · placa rev 1", lado / 2 + 3.2, 0.8)):
        t = pcbnew.PCB_TEXT(board)
        t.SetText(texto)
        t.SetPosition(_p(QR_CENTRO[0], QR_CENTRO[1] + dy))
        t.SetLayer(pcbnew.B_SilkS)
        t.SetMirrored(True)
        t.SetTextSize(pcbnew.VECTOR2I(pcbnew.FromMM(alto), pcbnew.FromMM(alto)))
        t.SetTextThickness(pcbnew.FromMM(alto * 0.15))
        board.Add(t)


def generar(destino: Path):
    board = pcbnew.CreateEmptyBoard() if hasattr(pcbnew, "CreateEmptyBoard") else pcbnew.BOARD()
    redes = {}

    def red(nombre):
        if nombre not in redes:
            ni = pcbnew.NETINFO_ITEM(board, "/" + nombre)   # mismo nombre que en el esquema (etiquetas locales)
            board.Add(ni)
            redes[nombre] = ni
        return redes[nombre]

    falta = [c["ref"] for c in COMPONENTES if c["ref"] not in POSICION]
    assert not falta, f"sin posición: {falta}"
    for c in COMPONENTES:
        lib, nombre = c["fp"].split(":")
        fp = pcbnew.FootprintLoad(f"{FOOTPRINTS}/{lib}.pretty", nombre)
        fp.SetFPID(pcbnew.LIB_ID(lib, nombre))
        fp.SetReference(c["ref"])
        fp.SetValue(c["valor"])
        fp.SetField("LCSC", c["lcsc"])
        fp.GetField("LCSC").SetVisible(False)
        board.Add(fp)
        x, y, giro = POSICION[c["ref"]]
        fp.SetPosition(_p(x, y))
        fp.SetOrientationDegrees(giro)
        nombres = NOMBRES_PINES.get(c["sym"], {})
        for pad in fp.Pads():
            n = c["pines"].get(pad.GetNumber())
            if n:
                pad.SetNet(red(n))
            elif pad.GetNumber() in nombres:
                libre = f"unconnected-({c['ref']}-{nombres[pad.GetNumber()]}-Pad{pad.GetNumber()})"
                if libre not in redes:
                    ni = pcbnew.NETINFO_ITEM(board, libre)
                    board.Add(ni)
                    redes[libre] = ni
                pad.SetNet(redes[libre])
            # Las vías térmicas de la huella del módulo son de 0,2 mm; JLCPCB estándar taladra desde 0,3 mm
            if pad.GetAttribute() == pcbnew.PAD_ATTRIB_PTH and pad.GetDrillSize().x < pcbnew.FromMM(0.3):
                pad.SetDrillSize(pcbnew.VECTOR2I(pcbnew.FromMM(0.3), pcbnew.FromMM(0.3)))
                if pad.GetSizeX() < pcbnew.FromMM(0.55):
                    pad.SetSize(pcbnew.F_Cu, pcbnew.VECTOR2I(pcbnew.FromMM(0.55), pcbnew.FromMM(0.55)))
        if c.get("dnp"):
            fp.SetDNP(True)
            fp.SetExcludedFromBOM(True)
            fp.SetExcludedFromPosFiles(True)

    _contorno(board)
    _serigrafia(board)
    _qr(board)
    gnd = red("GND")
    for capa in (pcbnew.F_Cu, pcbnew.B_Cu):
        _plano_masa(board, capa, gnd)

    ds = board.GetDesignSettings()
    ds.m_TrackMinWidth = pcbnew.FromMM(0.15)
    ds.m_MinClearance = pcbnew.FromMM(0.15)
    ds.m_ViasMinSize = pcbnew.FromMM(0.5)
    ds.m_MinThroughDrill = pcbnew.FromMM(0.3)
    ds.m_CopperEdgeClearance = pcbnew.FromMM(0.3)

    board.Save(str(destino))
    return board


if __name__ == "__main__":
    aqui = Path(__file__).parent
    generar(aqui / "puente.kicad_pcb")
    print("Placa:", aqui / "puente.kicad_pcb")
