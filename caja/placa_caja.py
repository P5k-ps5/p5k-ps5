"""Caja impresa en 3D para la placa p5k-ps5 (placa/, 62 × 30 mm, montada por JLCPCB).

Dos piezas que se imprimen sin soportes:
- La base: suelo, paredes con los dos huecos USB-C (CONSOLA a la izquierda, MANDO a la derecha) y un reborde
  y dos columnas en los que se apoya la placa. Nada de cobre ni de plástico grueso alrededor de la antena,
  que sobresale 6,5 mm por el borde de arriba de la placa: solo pared fina.
- La tapa: entra a presión con un labio, aprieta la placa con cuatro pivotes y lleva dos botones flexibles
  sobre RST y BOOT, un agujero para el LED y, grabados en la cara de arriba, el nombre, las etiquetas de los
  puertos y el QR de la web (el de la placa queda tapado por la caja).

Coordenadas: x de izquierda a derecha y y de abajo arriba sobre la placa (la esquina de abajo a la izquierda
de la placa en el origen; en KiCad la y va al revés), z hacia arriba. Medidas en mm.

Uso: python3 placa_caja.py [--vistas]  ->  placa/caja-base.stl, placa/caja-tapa.stl, placa/datos.json
(y placa/vistas.png con --vistas). Necesita manifold3d y numpy (y matplotlib para el texto y las vistas).
"""
import json
import sys
from pathlib import Path

import numpy as np
from manifold3d import CrossSection, FillRule, JoinType, Manifold

from caja import a_stl, caja_redondeada, cilindro_z, cubo

AQUI = Path(__file__).parent
PLACA = AQUI.parent / "placa"

# --- La placa (placa/pcb.py) ------------------------------------------------------------------------------
PL_ANCHO, PL_ALTO, PL_GROSOR = 62.0, 30.0, 1.6
ANTENA = 6.5                    # lo que el módulo sobresale por el borde de arriba
COMPONENTES = 3.3               # lo más alto sobre la placa (USB-C 3,2; módulo 3,1)
k = lambda x, y: (x, PL_ALTO - y)   # de coordenadas de KiCad (y hacia abajo) a las de la caja
USBC_Y = PL_ALTO - 9.0          # J1 y J2, a la misma altura
BOTONES = {"BOOT": k(4.8, 26.3), "RST": k(4.8, 19.5)}
BOTON_ALTO = 1.5                # TS-1187A sobre la placa
LED = k(15.5, 11.5)

# --- La caja -------------------------------------------------------------------------------------------
PARED = 1.8
HOLGURA = 0.3                   # alrededor de la placa
SUELO = 1.4
APOYO = 1.0                     # aire bajo la placa (debajo solo hay serigrafía)
AIRE = 0.8                      # sobre lo más alto de los componentes
TAPA = 1.4
LABIO, LABIO_ANCHO, AJUSTE = 1.4, 1.2, 0.1   # el labio de la tapa entra en la base con 0,1 mm de juego
RADIO = 3.0

X0, X1 = -HOLGURA, PL_ANCHO + HOLGURA                 # hueco interior
Y0, Y1 = -HOLGURA, PL_ALTO + ANTENA + HOLGURA
EX0, EX1, EY0, EY1 = X0 - PARED, X1 + PARED, Y0 - PARED, Y1 + PARED
Z_PLACA = SUELO + APOYO                               # cara de abajo de la placa
Z_ARRIBA = Z_PLACA + PL_GROSOR                        # cara de arriba de la placa
Z_TAPA = Z_ARRIBA + COMPONENTES + AIRE                # cara de abajo de la tapa (= alto de la base)
ALTO = Z_TAPA + TAPA

# Huecos USB-C: la boca del conector (8,94 × 3,26) con margen, y un rebaje por fuera para que la funda del
# cable llegue hasta el fondo
USB_Z = Z_ARRIBA + 1.6
USB_HUECO = (9.6, 4.0, 1.5)       # ancho, alto, radio
USB_REBAJE = (12.8, 6.6, 2.5, 1.0)  # ancho, alto, radio, profundidad

SEG = 64


def rect_redondeado_x(yc, zc, w, h, r, x0, x1):
    """Prisma de sección rectangular redondeada (w en y, h en z) entre x0 y x1"""
    cs = CrossSection.square((h - 2 * r, w - 2 * r)).translate((r, r)).offset(r, JoinType.Round, 2.0, SEG)
    m = cs.extrude(x1 - x0).rotate((0, 90, 0))
    b = m.bounding_box()
    return m.translate((x0 - b[0], yc - (b[1] + b[4]) / 2, zc - (b[2] + b[5]) / 2))


def texto(cadena, x, y, alto, profundo, z_cara, ancla="izq", negrita=True):
    """Texto grabado (para restar) en una cara horizontal a z_cara, leído desde arriba"""
    from matplotlib.font_manager import FontProperties
    from matplotlib.textpath import TextPath
    tp = TextPath((0, 0), cadena, size=alto, prop=FontProperties(family="DejaVu Sans", weight="bold" if negrita else "normal"))
    polis = [p for p in tp.to_polygons() if len(p) >= 3]
    cs = CrossSection([np.asarray(p, dtype=float) for p in polis], FillRule.EvenOdd)
    b = cs.bounds()  # (xmin, ymin, xmax, ymax)
    dx = {"izq": -b[0], "centro": -(b[0] + b[2]) / 2, "der": -b[2]}[ancla]
    cs = cs.translate((x + dx, y - (b[1] + b[3]) / 2))
    return cs.extrude(profundo + 0.2).translate((0, 0, z_cara - profundo))


def qr_grabado(cx, cy, modulo, profundo, z_cara):
    """Los módulos oscuros del QR de la web (placa/qr.json), grabados en la cara de arriba"""
    filas = json.loads((PLACA / "qr.json").read_text())["filas"]
    n = len(filas)
    lado = n * modulo
    x0, y_arriba = cx - lado / 2, cy + lado / 2
    piezas = []
    for i, fila in enumerate(filas):
        j = 0
        while j < n:
            if fila[j] in "1#X":
                k_ = j
                while k_ < n and fila[k_] in "1#X":
                    k_ += 1
                piezas.append(cubo(x0 + j * modulo, y_arriba - (i + 1) * modulo, z_cara - profundo,
                                   x0 + k_ * modulo, y_arriba - i * modulo, z_cara + 0.2))
                j = k_
            else:
                j += 1
    return Manifold.batch_boolean(piezas, __import__("manifold3d").OpType.Add) if piezas else Manifold()


# -------------------------------------------------------------------------------------------------------
def base():
    exterior = caja_redondeada(EX0, EY0, EX1 - EX0, EY1 - EY0, Z_TAPA, RADIO)
    interior = caja_redondeada(X0, Y0, X1 - X0, Y1 - Y0, Z_TAPA, 0.6, SUELO)
    b = exterior - interior
    # Reborde bajo los bordes de la placa (no bajo la antena) y dos columnas en medio
    reborde = cubo(X0, Y0, SUELO - 0.01, X1, PL_ALTO, Z_PLACA) - cubo(X0 + 1.4, Y0 + 1.4, 0, X1 - 1.4, PL_ALTO - 1.4, Z_PLACA + 1)
    b += reborde
    for x, y in ((40.0, 15.0), (52.0, 24.0)):
        b += cilindro_z(x, y, SUELO - 0.01, Z_PLACA, 4.0)
    # Los dos USB-C: hueco pasante y rebaje por fuera
    w, h, r = USB_HUECO
    rw, rh, rr, rp = USB_REBAJE
    for lado in ("izq", "der"):
        if lado == "izq":
            b -= rect_redondeado_x(USBC_Y, USB_Z, w, h, r, EX0 - 1, X0 + 0.5)
            b -= rect_redondeado_x(USBC_Y, USB_Z, rw, rh, rr, EX0 - 1, EX0 + rp)
        else:
            b -= rect_redondeado_x(USBC_Y, USB_Z, w, h, r, X1 - 0.5, EX1 + 1)
            b -= rect_redondeado_x(USBC_Y, USB_Z, rw, rh, rr, EX1 - rp, EX1 + 1)
    return b


def tapa():
    t = caja_redondeada(EX0, EY0, EX1 - EX0, EY1 - EY0, TAPA, RADIO, Z_TAPA)
    # Labio que entra en la base
    lx0, ly0, lx1, ly1 = X0 + AJUSTE, Y0 + AJUSTE, X1 - AJUSTE, Y1 - AJUSTE
    labio = caja_redondeada(lx0, ly0, lx1 - lx0, ly1 - ly0, LABIO, 0.5, Z_TAPA - LABIO)
    labio -= caja_redondeada(lx0 + LABIO_ANCHO, ly0 + LABIO_ANCHO, lx1 - lx0 - 2 * LABIO_ANCHO, ly1 - ly0 - 2 * LABIO_ANCHO, LABIO + 1, 0.3, Z_TAPA - LABIO - 0.5)
    t += labio
    # Pivotes que aprietan la placa en sitios libres de componentes
    for x, y in ((1.1, PL_ALTO - 1.4), (1.1, 15.0), (PL_ANCHO - 1.4, PL_ALTO - 1.4), (PL_ANCHO - 1.4, 1.4)):
        t += cilindro_z(x, y, Z_ARRIBA, Z_TAPA + 0.01, 1.8)
    # Botones flexibles: una lengüeta sujeta por el lado de dentro, con un tetón que llega al pulsador
    for nombre, (bx, by) in BOTONES.items():
        ranura = cubo(bx - 3.5, by - 3.1, Z_TAPA - LABIO - 1, bx + 2.8, by + 3.1, ALTO + 1)
        ranura -= cubo(bx - 2.8, by - 2.4, Z_TAPA - LABIO - 2, bx + 3.5, by + 2.4, ALTO + 2)
        t -= ranura
        t += cilindro_z(bx, by, Z_ARRIBA + BOTON_ALTO + 0.3, Z_TAPA + 0.01, 2.6)
        t -= texto(nombre, bx + 4.6, by, 2.0, 0.5, ALTO)
    # LED: agujero pasante
    t -= cilindro_z(LED[0], LED[1], Z_TAPA - 1, ALTO + 1, 2.4)
    # Grabados en la cara de arriba: nombre, puertos y QR
    t -= texto("p5k-ps5", (EX0 + EX1) / 2 - 6, PL_ALTO + ANTENA / 2 + 0.4, 4.2, 0.6, ALTO, "centro")
    t -= texto("< CONSOLA", 0.8, USBC_Y + 6.3, 2.0, 0.5, ALTO)
    t -= texto("MANDO >", PL_ANCHO - 0.8, USBC_Y + 6.3, 2.0, 0.5, ALTO, "der")
    t -= qr_grabado(44.5, 13.0, 0.8, 0.6, ALTO)
    # El rebaje de los USB-C sigue en la tapa si llega a ella
    rw, rh, rr, rp = USB_REBAJE
    t -= rect_redondeado_x(USBC_Y, USB_Z, rw, rh, rr, EX0 - 1, EX0 + rp)
    t -= rect_redondeado_x(USBC_Y, USB_Z, rw, rh, rr, EX1 - rp, EX1 + 1)
    return t


def vistas(salida, b, t):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from mpl_toolkits.mplot3d.art3d import Poly3DCollection
    fig = plt.figure(figsize=(14, 6), dpi=130)
    for n, (titulo, elev, azim, separar) in enumerate((("Montada", 28, -58, 0), ("Abierta", 32, -58, 14), ("Tapa por arriba", 89, -90, 0))):
        ax = fig.add_subplot(1, 3, n + 1, projection="3d")
        for m, color, dz in ((b, "#2b2d33", 0), (t, "#d9dbe0", separar)):
            mesh = m.to_mesh()
            v = np.asarray(mesh.vert_properties)[:, :3] + np.array([0, 0, dz])
            tri = np.asarray(mesh.tri_verts)
            ax.add_collection3d(Poly3DCollection(v[tri], facecolor=color, edgecolor="none", alpha=1.0, linewidth=0))
        ax.set_xlim(EX0, EX1); ax.set_ylim(EY0 - 10, EY1 + 10); ax.set_zlim(-14, 40)
        ax.view_init(elev, azim); ax.set_box_aspect((EX1 - EX0, EY1 - EY0 + 20, 54)); ax.axis("off")
        ax.set_title(titulo)
    fig.tight_layout()
    fig.savefig(salida)


if __name__ == "__main__":
    d = AQUI / "placa"
    d.mkdir(exist_ok=True)
    b, t = base(), tapa()
    a_stl(b, d / "caja-base.stl")
    # La tapa se guarda como se imprime: boca abajo y apoyada en la cama (como la de caja.py)
    a_stl(t.mirror((0, 0, 1)).translate((0, 0, ALTO)), d / "caja-tapa.stl")
    datos = {
        "medidas": [round(EX1 - EX0, 1), round(EY1 - EY0, 1), round(ALTO, 1)],
        "volumen_cm3": {"base": round(b.volume() / 1000, 1), "tapa": round(t.volume() / 1000, 1)},
        "pared": PARED, "suelo": SUELO, "tapa": TAPA, "alto": round(ALTO, 2), "placa_z": Z_PLACA,
    }
    (d / "datos.json").write_text(json.dumps(datos, ensure_ascii=False, indent=1) + "\n")
    print(f"placa: {datos['medidas'][0]} × {datos['medidas'][1]} × {datos['medidas'][2]} mm, "
          f"base {datos['volumen_cm3']['base']} cm³, tapa {datos['volumen_cm3']['tapa']} cm³")
    if "--vistas" in sys.argv:
        vistas(d / "vistas.png", b, t)
