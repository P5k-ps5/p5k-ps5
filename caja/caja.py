#!/usr/bin/env python3
"""Caja impresa en 3D para el puente: ESP32-S3 (YD-ESP32-S3 / DevKitC-1) + MAX3421E (DuinoFUN USB mini).

Distribución (la más compacta sin quitar los pines del ESP32):
- El ESP32 arriba, boca arriba, con sus pines hacia abajo y los Dupont hembra enchufados por debajo.
- El MAX3421E tumbado debajo del ESP32, entre las dos filas de pines, con sitio debajo para sus pines y los
  cables soldados a ellos (no hace falta cortar nada). Lo sujetan su USB-A (en su agujero) y una ranura detrás.
- Todos los conectores en la misma cara: los dos USB-C del ESP32 arriba y el USB-A del mando abajo.
  El extremo de la antena del ESP32 queda libre (sin metal ni placas encima): mejor WiFi.
- Tapa a presión con el botón BOOT (lengüeta flexible), un agujero para RST (con un clip) y otro para el LED.

Coordenadas (mm): x a lo largo (0 = cara de los conectores), y a lo ancho, z hacia arriba (0 = suelo por fuera).
Las medidas de las placas salen de las fotos (los pines van a 2,54 mm) y del DevKitC-1 oficial (62,74 × 25,4).
Las que conviene comprobar con una regla antes de imprimir están marcadas con «COMPROBAR».

Uso: python3 caja.py  ->  en cada carpeta (conectable/, compacta/, plana/): caja-base.stl, caja-tapa.stl,
prueba-puertos.stl, visor.html (el montaje en 3D, para el navegador) y vistas.png con --vistas
"""
import struct
import sys
from pathlib import Path

import numpy as np
from manifold3d import CrossSection, JoinType, Manifold

# ---------------------------------------------------------------------------------------------------------
# Medidas de las placas
# ---------------------------------------------------------------------------------------------------------
# Medidas sacadas de fotos de las placas reales (YD-ESP32-S3 N16R8 y MAX3421E USB mini), con el paso de los pines
# (2,54 mm) como regla: ±0,5 mm. Lo marcado COMPROBAR conviene confirmarlo con una regla antes de encargar la caja.
ESP_LARGO = 57.0           # placa del ESP32 (sin la antena). Es más corta y más ancha que el DevKitC-1 oficial
ESP_ANCHO = 27.7           # COMPROBAR
FILAS_SEPARACION = 25.4    # entre las dos filas de pines (1 pulgada en esta placa)
FILA_BORDE = (ESP_ANCHO - FILAS_SEPARACION) / 2   # del borde de la placa al centro de su fila de pines
ESP_GROSOR = 1.6
ANTENA_SOBRESALE = 6.5     # lo que el módulo (la parte negra de la antena) sale de la placa
USBC_SOBRESALE = 0.6       # COMPROBAR: lo que la boca de los USB-C sale del borde de la placa
USBC_ANCHO, USBC_ALTO = 8.94, 3.26
# Centro de cada USB-C medido desde el borde de la fila de pines GND/TX/RX (la de los botones)
USBC_SEPARACION = 11.5     # COMPROBAR: de centro a centro de los dos USB-C
USBC_Y = (ESP_ANCHO / 2 - USBC_SEPARACION / 2, ESP_ANCHO / 2 + USBC_SEPARACION / 2)   # la pareja va centrada en la placa
COMPONENTES_ALTO = 3.3     # lo más alto encima de la placa (USB-C, módulo)
# Botones y LED: (desde el borde de los USB-C, desde el borde de la fila GND/TX/RX)
BOOT = (28.4, 8.3)
RST = (33.8, 8.3)
LED = (18.6, 18.5)         # el LED RGB
BOTON_ALTO = 2.0           # COMPROBAR: altura del pulsador sobre la placa
PIN_PASO = 2.54
PIN_PRIMERO = 2.05         # del borde de los USB-C al primer pin
ESPACIADOR = 2.5           # plástico de los pines (por debajo de la placa)
DUPONT = 14.0              # largo de la hembra Dupont
CODO_CABLE = 3.0           # sitio para doblar el cable al salir de la hembra

MODULO_ANCHO, MODULO_LARGO = 18.0, 25.5   # módulo ESP32-S3-WROOM-1 (con la antena)

MAX_LARGO, MAX_ANCHO, MAX_GROSOR = 38.3, 18.5, 1.6
USBA_ANCHO, USBA_ALTO = 13.4, 7.0      # COMPROBAR (en las fotos sale entre 6,5 y 7 de alto)
USBA_SOBRESALE = 7.4                   # lo que el USB-A sale de la placa del MAX
# Tres formas de montarlo (se generan las tres):
# - «conectable»: cables soldados por ARRIBA del MAX (pines de debajo cortados a ras) y con hembras Dupont
#   enchufadas a los pines del ESP32 (se puede desmontar). Las hembras miden 14 mm: caja más alta.
# - «compacta»: cables soldados por arriba del MAX y directamente a los pines del ESP32 (sin Dupont).
# - «plana»: sin los plásticos de los pines (salen tirando) y con los pines cortados a ras en las dos placas;
#   cables soldados a los muñones. El MAX tumbado en el suelo y el ESP32 justo encima de su USB-A. Los USB-C
#   en un extremo y el USB-A en el contrario (debajo de la antena: comprobar que la WiFi no pierde mucho).
VARIANTE = "conectable"
MAX_DEBAJO = 1.5           # lo que queda de los pines por debajo del MAX después de cortarlos a ras
MAX_DEBAJO_PLANA = 1.0     # en la plana: solo las gotas de estaño por debajo del MAX
PIN_LARGO = 6.0            # lo que salen los pines del ESP32 por debajo de su plástico

# ---------------------------------------------------------------------------------------------------------
# Caja
# ---------------------------------------------------------------------------------------------------------
PARED = 2.0
SUELO = 1.6
TAPA = 1.6
RADIO = 3.0                # esquinas redondeadas
HOLGURA = 0.3              # entre las placas y las paredes
AJUSTE = 0.2               # en los agujeros de los conectores
HUECO_TAPA = 0.15          # entre la pestaña de la tapa y las paredes
CARA_CLAVIJA = 1.0         # rebaje por fuera de los conectores: la clavija entra hasta el fondo

# Alturas (z): se calculan en configurar() según la variante
def configurar(variante):
    """Calcula las medidas que dependen de la variante (conectable, compacta o plana)"""
    global VARIANTE, SUELO, TAPA, ESP_Z, ESP_ARRIBA, TECHO, MAX_Z, USBA_Z, X_ESP, LARGO, ANCHO, Y_ESP, ALTO_BASE, X_USB, X_MAX, Y_MAX
    VARIANTE = variante
    SUELO, TAPA = (1.2, 1.2) if variante == "plana" else (1.6, 1.6)
    MAX_Z = SUELO + (MAX_DEBAJO_PLANA if variante == "plana" else MAX_DEBAJO)
    USBA_Z = MAX_Z + MAX_GROSOR                              # el USB-A va encima de la placa del MAX
    if variante == "conectable":
        ESP_Z = SUELO + CODO_CABLE + DUPONT + ESPACIADOR      # cara de abajo de la placa del ESP32
    elif variante == "compacta":
        ESP_Z = SUELO + 2.5 + PIN_LARGO + ESPACIADOR          # cables soldados a la punta de los pines
    else:
        ESP_Z = USBA_Z + USBA_ALTO + 0.5                      # el ESP32 casi tocando el USB-A
    ESP_ARRIBA = ESP_Z + ESP_GROSOR
    # cara de dentro de la tapa. En la plana, la pestaña de la tapa no va por delante ni por detrás (chocaría
    # con los USB-C y el módulo) y el techo puede ir casi pegado a los componentes
    TECHO = ESP_ARRIBA + COMPONENTES_ALTO + (0.6 if variante == "plana" else 2.3)

    # Largo y ancho
    X_ESP = PARED                                           # borde de la placa del ESP32 (el de los USB-C)
    LARGO = X_ESP + ESP_LARGO + ANTENA_SOBRESALE + 0.6 + PARED
    ANCHO = ESP_ANCHO + 2 * HOLGURA + 2 * PARED
    Y_ESP = PARED + HOLGURA                                 # borde de la fila GND/TX/RX
    ALTO_BASE = TECHO
    X_USB = X_ESP - USBC_SOBRESALE                          # boca de los USB-C (dentro de la pared)
    if variante == "plana":
        # el USB-A sale por la cara contraria, con la boca a la misma distancia de fuera que la de los USB-C
        X_MAX = LARGO - X_USB - USBA_SOBRESALE - MAX_LARGO
    else:
        X_MAX = X_USB + USBA_SOBRESALE                      # la boca del USB-A, alineada con la de los USB-C
    Y_MAX = ANCHO / 2 - MAX_ANCHO / 2
    # el USB-A del MAX no puede tocar la placa del ESP32
    assert USBA_Z + USBA_ALTO + 0.5 <= ESP_Z, f"el MAX no cabe debajo del ESP32 ({USBA_Z + USBA_ALTO:.1f} > {ESP_Z:.1f})"


configurar(VARIANTE)

SEG = 64


def caja_redondeada(x, y, w, h, alto, r, z=0.0):
    r = min(r, w / 2 - 0.01, h / 2 - 0.01)
    if r <= 0:
        return Manifold.cube((w, h, alto)).translate((x, y, z))
    cs = CrossSection.square((w - 2 * r, h - 2 * r)).translate((r, r)).offset(r, JoinType.Round, 2.0, SEG)
    return cs.extrude(alto).translate((x, y, z))


def cubo(x0, y0, z0, x1, y1, z1):
    return Manifold.cube((x1 - x0, y1 - y0, z1 - z0)).translate((x0, y0, z0))


def hueco_frontal(yc, zc, w, h, r, prof):
    """Agujero rectangular redondeado en la cara x=0, de profundidad prof (hacia dentro)"""
    # Al girar 90° sobre y, la x del perfil pasa a ser la altura (z) y la y sigue siendo el ancho:
    # el perfil se dibuja con el alto en x y el ancho en y
    cs = CrossSection.square((h - 2 * r, w - 2 * r)).translate((r, r)).offset(r, JoinType.Round, 2.0, SEG)
    m = cs.extrude(prof).rotate((0, 90, 0))
    b = m.bounding_box()
    m = m.translate((-b[0], yc - (b[1] + b[4]) / 2, zc - (b[2] + b[5]) / 2))
    return m


def hueco_trasero(yc, zc, w, h, r, prof):
    """Lo mismo en la cara contraria (x = LARGO)"""
    return hueco_frontal(yc, zc, w, h, r, prof).mirror((1, 0, 0)).translate((LARGO, 0, 0))


def cilindro_z(x, y, z0, z1, d):
    return Manifold.cylinder(z1 - z0, d / 2, d / 2, SEG).translate((x, y, z0))


# ---------------------------------------------------------------------------------------------------------
def base():
    exterior = caja_redondeada(0, 0, LARGO, ANCHO, ALTO_BASE, RADIO)
    interior = caja_redondeada(PARED, PARED, LARGO - 2 * PARED, ANCHO - 2 * PARED, ALTO_BASE, 0.3, SUELO)
    b = exterior - interior

    # Conectores en la cara x=0. Agujero justo para el conector (lo sujeta) y, por fuera, un rebaje del
    # tamaño de la clavija para que entre hasta el fondo.
    zc_c = ESP_ARRIBA + USBC_ALTO / 2
    ys = [Y_ESP + v for v in USBC_Y]
    for y in ys:
        b -= hueco_frontal(y, zc_c, USBC_ANCHO + 2 * AJUSTE, USBC_ALTO + 2 * AJUSTE, 1.4, PARED + 0.1).translate((-0.05, 0, 0))
    ancho_rebaje = (max(ys) - min(ys)) + 12.6
    zc_a = USBA_Z + USBA_ALTO / 2
    plana = VARIANTE == "plana"
    hueco = hueco_trasero if plana else hueco_frontal
    sale = 0.05 if plana else -0.05
    b -= hueco(ANCHO / 2, zc_a, USBA_ANCHO + 2 * AJUSTE, USBA_ALTO + 2 * AJUSTE, 0.6, PARED + 0.1).translate((sale, 0, 0))
    # Rebajes de las clavijas. Si quedan casi pegados (variante compacta), uno solo con los tres conectores.
    c_abajo, c_arriba = zc_c - 3.3, zc_c + 3.3
    a_abajo, a_arriba = zc_a - 4.7, zc_a + 4.7
    if plana:
        b -= hueco_frontal(sum(ys) / 2, zc_c, ancho_rebaje, 6.6, 2.0, CARA_CLAVIJA).translate((-0.01, 0, 0))
        b -= hueco_trasero(ANCHO / 2, zc_a, 16.6, 9.4, 1.5, CARA_CLAVIJA).translate((0.01, 0, 0))
    elif c_abajo - a_arriba < 2.0:
        y_med = (sum(ys) / 2 + ANCHO / 2) / 2
        ancho = max(ancho_rebaje, 16.6) + abs(sum(ys) / 2 - ANCHO / 2)
        b -= hueco_frontal(y_med, (a_abajo + c_arriba) / 2, ancho, c_arriba - a_abajo, 2.0, CARA_CLAVIJA).translate((-0.01, 0, 0))
    else:
        b -= hueco_frontal(sum(ys) / 2, zc_c, ancho_rebaje, 6.6, 2.0, CARA_CLAVIJA).translate((-0.01, 0, 0))
        b -= hueco_frontal(ANCHO / 2, zc_a, 16.6, 9.4, 1.5, CARA_CLAVIJA).translate((-0.01, 0, 0))

    if plana:
        # Apoyos del ESP32: un pilar en el centro, entre los USB-C y el MAX, y dos postes bajo los bordes de la
        # antena (lo que sale de la placa), a los lados del USB-A: plástico, no molesta a la WiFi. El extremo de
        # los USB-C lo sujetan sus agujeros.
        x_pilar0, x_pilar1 = X_ESP + 8, X_MAX - 3
        b += caja_redondeada(x_pilar0, ANCHO / 2 - 5, x_pilar1 - x_pilar0, 10, ESP_Z - SUELO, 1.5, SUELO)
        x_post0, x_post1 = max(X_MAX + MAX_LARGO, X_ESP + ESP_LARGO) + 0.5, X_ESP + ESP_LARGO + ANTENA_SOBRESALE - 0.5
        borde_usba = USBA_ANCHO / 2 + AJUSTE + 0.5
        for s_ in (-1, 1):
            y0, y1 = sorted((ANCHO / 2 + s_ * borde_usba, ANCHO / 2 + s_ * (borde_usba + 3.0)))
            b += cubo(x_post0, y0, SUELO - 0.01, x_post1, y1, ESP_ARRIBA)
    else:
        # Apoyos del ESP32: un pilar en el centro (más allá del MAX, entre las filas de pines) y un poste bajo la
        # antena (plástico: no molesta a la WiFi). El extremo de los USB-C lo sujetan sus agujeros.
        x_pilar0 = X_MAX + MAX_LARGO + 1.5
        b += caja_redondeada(x_pilar0, ANCHO / 2 - 5, X_ESP + ESP_LARGO - 3 - x_pilar0, 10, ESP_Z - SUELO, 1.5, SUELO)
        x_ant = X_ESP + ESP_LARGO + 0.8
        b += caja_redondeada(x_ant, ANCHO / 2 - 4, ANTENA_SOBRESALE - 1.6, 8, ESP_ARRIBA - SUELO, 1.0, SUELO)

    # El MAX3421E: delante lo sujeta el USB-A en su agujero. Detrás, por el centro (lejos de las filas de pines),
    # un apoyo debajo del borde y una pinza flexible que se engancha por encima al bajar la placa (clic).
    # Se dibuja para el MAX con el USB-A en x = 0 y, en la plana, se refleja (el USB-A va en la otra cara).
    x_fin = X_MAX + MAX_LARGO if not plana else LARGO - X_MAX
    pinza = cubo(x_fin - 2.5, ANCHO / 2 - 3, SUELO - 0.01, x_fin, ANCHO / 2 + 3, MAX_Z)           # apoyo
    pinza += cubo(x_fin + 0.15, ANCHO / 2 - 4, SUELO - 0.01, x_fin + 1.45, ANCHO / 2 + 4, USBA_Z + 1.5)
    # uña: por debajo plana (sujeta la placa), por encima en rampa (al empujar la placa, el brazo se aparta)
    perfil = CrossSection([[(x_fin + 0.2, USBA_Z + 0.1), (x_fin + 0.2, USBA_Z + 1.5), (x_fin - 0.7, USBA_Z + 0.5),
                            (x_fin - 0.7, USBA_Z + 0.1)]])
    pinza += perfil.extrude(8).rotate((90, 0, 0)).translate((0, ANCHO / 2 + 4, 0))
    if plana:
        pinza = pinza.mirror((1, 0, 0)).translate((LARGO, 0, 0))
    b += pinza

    # Ranuras para los salientes de la tapa (cierre a presión)
    for y, s in ((PARED, -1), (ANCHO - PARED, 1)):
        for x in (LARGO * 0.3, LARGO * 0.7):
            b -= cubo(x - 4, y - 0.35 if s < 0 else y - 0.01, ALTO_BASE - 1.6, x + 4, y + 0.01 if s < 0 else y + 0.35, ALTO_BASE - 0.8)
    return b


def tapa():
    t = caja_redondeada(0, 0, LARGO, ANCHO, TAPA, RADIO, ALTO_BASE)
    # Pestaña que entra en la caja
    g = PARED + HUECO_TAPA
    lip_alto = 1.8
    aro = caja_redondeada(g, g, LARGO - 2 * g, ANCHO - 2 * g, lip_alto, 0.3, ALTO_BASE - lip_alto) - \
        caja_redondeada(g + 1.2, g + 1.2, LARGO - 2 * g - 2.4, ANCHO - 2 * g - 2.4, lip_alto + 0.1, 0, ALTO_BASE - lip_alto - 0.05)
    if VARIANTE == "plana":
        # con el techo tan bajo, la pestaña chocaría con los USB-C y con el módulo: solo en los laterales
        aro -= cubo(-1, -1, 0, X_ESP + 9, ANCHO + 1, ALTO_BASE + 1)
        aro -= cubo(LARGO - 9, -1, 0, LARGO + 1, ANCHO + 1, ALTO_BASE + 1)
    t += aro
    for y, s in ((g, -1), (ANCHO - g, 1)):
        for x in (LARGO * 0.3, LARGO * 0.7):
            t += cubo(x - 3.5, y - 0.3 if s < 0 else y, ALTO_BASE - 1.5, x + 3.5, y if s < 0 else y + 0.3, ALTO_BASE - 0.9)

    # Topes que aprietan el ESP32 contra sus apoyos: sobre el blindaje del módulo y sobre los USB-C
    z_mod = ESP_ARRIBA + 3.1 + 0.2
    x_mod0 = X_ESP + ESP_LARGO + ANTENA_SOBRESALE - MODULO_LARGO
    t += cubo(x_mod0 + 4, ANCHO / 2 - 6, z_mod, x_mod0 + 6, ANCHO / 2 + 6, ALTO_BASE + 0.01)
    z_usb = ESP_ARRIBA + USBC_ALTO + 0.25
    for v in USBC_Y:
        y = Y_ESP + v
        t += cubo(X_ESP + 1, y - 3, z_usb, X_ESP + 4, y + 3, ALTO_BASE + 0.01)

    # LED: ventanita
    t -= cilindro_z(X_ESP + LED[0], Y_ESP + LED[1], ALTO_BASE - 1, ALTO_BASE + TAPA + 1, 3.0)
    # RST: agujero pequeño (se pulsa con un clip: así no se reinicia sin querer)
    t -= cilindro_z(X_ESP + RST[0], Y_ESP + RST[1], ALTO_BASE - 1, ALTO_BASE + TAPA + 1, 2.2)
    # BOOT: lengüeta flexible con un pulsador por debajo
    bx, by = X_ESP + BOOT[0], Y_ESP + BOOT[1]
    ranura = 0.7
    largo_l, ancho_l = 13.0, 7.0
    x0 = bx - 3.0                                     # la lengüeta sale hacia los USB-C (bisagra en x0 - ...)
    u = cubo(x0 - largo_l + 3.0, by - ancho_l / 2 - ranura, ALTO_BASE - 0.1, x0 + 6.0, by + ancho_l / 2 + ranura, ALTO_BASE + TAPA + 0.1)
    lengueta = cubo(x0 - largo_l + 3.0, by - ancho_l / 2, ALTO_BASE - 0.2, x0 + 6.0 - ranura, by + ancho_l / 2, ALTO_BASE + TAPA + 0.2)
    t -= (u - lengueta)
    # la bisagra: la lengüeta sigue unida por el lado de los USB-C; adelgazarla un poco para que flexe
    t -= cubo(x0 - largo_l + 3.0, by - ancho_l / 2, ALTO_BASE + TAPA - 0.6, x0 - largo_l + 5.0, by + ancho_l / 2, ALTO_BASE + TAPA + 0.1)
    z_boton = ESP_ARRIBA + BOTON_ALTO + 0.3
    t += cilindro_z(bx, by, z_boton, ALTO_BASE + 0.01, 3.0)
    # marca en la tapa encima de BOOT
    t -= cilindro_z(bx, by, ALTO_BASE + TAPA - 0.4, ALTO_BASE + TAPA + 0.1, 5.0) - cilindro_z(bx, by, ALTO_BASE + TAPA - 0.5, ALTO_BASE + TAPA + 0.2, 4.0)
    # para imprimir: boca abajo (la cara de fuera sobre la cama)
    return t.mirror((0, 0, 1)).translate((0, 0, ALTO_BASE + TAPA))


def prueba_puertos():
    """Solo la cara de los conectores y 12 mm de caja: se imprime en un rato y sirve para comprobar que los
    USB-C y el USB-A encajan antes de imprimir la caja entera. En la plana, las dos caras (dos piezas)"""
    corte = cubo(-1, -1, -1, 12, ANCHO + 1, ALTO_BASE + 1)
    if VARIANTE == "plana":
        corte += cubo(LARGO - 12, -1, -1, LARGO + 1, ANCHO + 1, ALTO_BASE + 1)
    return base() ^ corte


# ---------------------------------------------------------------------------------------------------------
def a_stl(m: Manifold, ruta: Path):
    mesh = m.to_mesh()
    v = np.asarray(mesh.vert_properties)[:, :3].astype(np.float32)
    t = np.asarray(mesh.tri_verts).astype(np.int64)
    with open(ruta, "wb") as f:
        f.write(b"puente de mando".ljust(80, b" "))
        f.write(struct.pack("<I", len(t)))
        for a, b_, c in t:
            p, q, r = v[a], v[b_], v[c]
            n = np.cross(q - p, r - p)
            ln = np.linalg.norm(n)
            n = n / ln if ln else n
            f.write(struct.pack("<12fH", *n, *p, *q, *r, 0))


def vistas(salida: Path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from mpl_toolkits.mplot3d.art3d import Poly3DCollection

    def dibujar(ax, m, color, alfa=1.0):
        mesh = m.to_mesh()
        v = np.asarray(mesh.vert_properties)[:, :3]
        t = np.asarray(mesh.tri_verts)
        tri = v[t]
        n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-9
        luz = np.array([-0.45, -0.6, 0.66]); luz /= np.linalg.norm(luz)
        k = 0.35 + 0.65 * np.clip(n @ luz, 0, 1)
        col = np.clip(np.array(color)[None, :] * k[:, None], 0, 1)
        pc = Poly3DCollection(tri, facecolors=np.c_[col, np.full(len(col), alfa)], edgecolors="none")
        ax.add_collection3d(pc)

    def preparar(ax, titulo, lim):
        ax.set_xlim(lim[0]); ax.set_ylim(lim[1]); ax.set_zlim(lim[2])
        ax.set_box_aspect([lim[0][1] - lim[0][0], lim[1][1] - lim[1][0], lim[2][1] - lim[2][0]])
        ax.set_axis_off(); ax.set_title(titulo, fontsize=11)

    # Placas (para ver que caben)
    esp = cubo(X_ESP, Y_ESP, ESP_Z, X_ESP + ESP_LARGO, Y_ESP + ESP_ANCHO, ESP_ARRIBA)
    x_mod0 = X_ESP + ESP_LARGO + ANTENA_SOBRESALE - MODULO_LARGO
    modulo = cubo(x_mod0, Y_ESP + (ESP_ANCHO - MODULO_ANCHO) / 2, ESP_ARRIBA, X_ESP + ESP_LARGO + ANTENA_SOBRESALE, Y_ESP + (ESP_ANCHO + MODULO_ANCHO) / 2, ESP_ARRIBA + 3.1)
    usbs = [cubo(X_USB, Y_ESP + v - USBC_ANCHO / 2, ESP_ARRIBA, X_USB + 7.35, Y_ESP + v + USBC_ANCHO / 2, ESP_ARRIBA + USBC_ALTO) for v in USBC_Y]
    filas = [cubo(X_ESP + 0.2, Y_ESP + yy - 1.27, ESP_Z - ESPACIADOR, X_ESP + ESP_LARGO - 0.2, Y_ESP + yy + 1.27, ESP_Z) for yy in (FILA_BORDE, ESP_ANCHO - FILA_BORDE)]
    dup = [cubo(X_ESP + PIN_PRIMERO + i * PIN_PASO - 1.27, Y_ESP + ESP_ANCHO - FILA_BORDE - 1.27, ESP_Z - ESPACIADOR - DUPONT,
                X_ESP + PIN_PRIMERO + i * PIN_PASO + 1.27, Y_ESP + ESP_ANCHO - FILA_BORDE + 1.27, ESP_Z - ESPACIADOR) for i in (0, 1, 3, 4, 5, 6, 7, 20, 21)]
    maxp = cubo(X_MAX, Y_MAX, MAX_Z, X_MAX + MAX_LARGO, Y_MAX + MAX_ANCHO, USBA_Z)
    x_usba = LARGO - X_USB - 15 if VARIANTE == "plana" else X_USB
    usba = cubo(x_usba, ANCHO / 2 - USBA_ANCHO / 2, USBA_Z, x_usba + 15, ANCHO / 2 + USBA_ANCHO / 2, USBA_Z + USBA_ALTO)
    if VARIANTE == "plana":
        filas, dup = [], []                           # sin plásticos: los pines cortados a ras

    b, tp = base(), tapa()
    tapa_puesta = tp.mirror((0, 0, 1)).translate((0, 0, ALTO_BASE + TAPA))
    lim = ((-5, LARGO + 5), (-5, ANCHO + 5), (-2, ALTO_BASE + TAPA + 2))
    fig = plt.figure(figsize=(16, 10))

    ax = fig.add_subplot(2, 2, 1, projection="3d")
    dibujar(ax, b, (0.82, 0.84, 0.88)); ax.view_init(24, -128)
    preparar(ax, "Caja (cara de los USB-C)" if VARIANTE == "plana" else "Caja (cara de los conectores)", lim)

    ax = fig.add_subplot(2, 2, 2, projection="3d")
    dibujar(ax, b - cubo(-1, ANCHO / 2, -1, LARGO + 1, ANCHO + 1, ALTO_BASE + 5), (0.82, 0.84, 0.88))
    for m, c in [(esp, (0.1, 0.1, 0.12)), (modulo, (0.75, 0.75, 0.72)), (maxp, (0.12, 0.3, 0.75)), (usba, (0.8, 0.8, 0.82)),
                 *[(u, (0.85, 0.85, 0.88)) for u in usbs], *[(f, (0.95, 0.8, 0.1)) for f in filas], *[(d, (0.15, 0.15, 0.15)) for d in dup]]:
        dibujar(ax, m, c)
    ax.view_init(12, -70)
    preparar(ax, "Por dentro (corte): ESP32 arriba, MAX3421E abajo", lim)

    ax = fig.add_subplot(2, 2, 3, projection="3d")
    dibujar(ax, b, (0.82, 0.84, 0.88)); dibujar(ax, tapa_puesta, (0.25, 0.45, 0.95)); ax.view_init(30, -55)
    preparar(ax, "Cerrada: BOOT (lengüeta), RST (agujero) y LED", lim)

    ax = fig.add_subplot(2, 2, 4, projection="3d")
    dibujar(ax, b, (0.82, 0.84, 0.88)); dibujar(ax, tapa_puesta, (0.25, 0.45, 0.95))
    if VARIANTE == "plana":
        ax.view_init(8, 20)
        preparar(ax, "Cara del USB-A (mando); los USB-C, en la cara contraria", lim)
    else:
        ax.view_init(8, -160)
        preparar(ax, "Conectores: USB-C (consola y COM) arriba, USB-A (mando) abajo", lim)

    plt.tight_layout()
    plt.savefig(salida, dpi=110)


# Cables del ESP32 al MAX3421E (variante plana y compacta: soldados): (pin de la fila sin TX/RX del ESP32, contando
# desde la antena, a qué va, color). Las posiciones en el MAX del visor son aproximadas: solo para ver el montaje.
CABLES = [(1, "3V3 → VCC", "#8e44ad"), (12, "GPIO8 → MAX_RST", "#ff7eb6"), (15, "GPIO9 → INT", "#9aa0a6"),
          (16, "GPIO10 → SS", "#e53935"), (17, "GPIO11 → CLK", "#fb8c00"), (18, "GPIO12 → MOSI", "#fdd835"),
          (19, "GPIO13 → MISO", "#43a047"), (21, "5V → VBUS", "#1e88e5"), (22, "GND → GND", "#795548")]


def visor(salida: Path):
    """Página con el montaje en 3D (three.js): se abre en el navegador, sin instalar nada"""
    import json

    def malla(m):
        mesh = m.to_mesh()
        v = np.asarray(mesh.vert_properties)[:, :3]
        return {"pos": [round(float(x), 2) for x in v.ravel()], "idx": [int(i) for i in np.asarray(mesh.tri_verts).ravel()]}

    def caja_(nombre, grupo, x0, y0, z0, x1, y1, z1, color, metal=False):
        return {"nombre": nombre, "grupo": grupo, "min": [x0, y0, z0], "max": [x1, y1, z1], "color": color, "metal": metal}

    plana = VARIANTE == "plana"
    piezas = []
    # ESP32
    piezas.append(caja_("ESP32-S3", "esp", X_ESP, Y_ESP, ESP_Z, X_ESP + ESP_LARGO, Y_ESP + ESP_ANCHO, ESP_ARRIBA, "#1b1d22"))
    x_mod0 = X_ESP + ESP_LARGO + ANTENA_SOBRESALE - MODULO_LARGO
    piezas.append(caja_("Módulo WiFi (antena al final)", "esp", x_mod0, Y_ESP + (ESP_ANCHO - MODULO_ANCHO) / 2, ESP_ARRIBA, X_ESP + ESP_LARGO + ANTENA_SOBRESALE,
                        Y_ESP + (ESP_ANCHO + MODULO_ANCHO) / 2, ESP_ARRIBA + 3.1, "#c9ccd1", True))
    piezas.append(caja_("Antena", "esp", X_ESP + ESP_LARGO - 0.5, Y_ESP + (ESP_ANCHO - MODULO_ANCHO) / 2, ESP_ARRIBA - 0.01, X_ESP + ESP_LARGO + ANTENA_SOBRESALE,
                        Y_ESP + (ESP_ANCHO + MODULO_ANCHO) / 2, ESP_ARRIBA + 0.8, "#2a2d33"))
    for v, n in zip(USBC_Y, ("USB-C (COM)", "USB-C (consola)")):
        piezas.append(caja_(n, "esp", X_USB, Y_ESP + v - USBC_ANCHO / 2, ESP_ARRIBA, X_USB + 7.35, Y_ESP + v + USBC_ANCHO / 2,
                            ESP_ARRIBA + USBC_ALTO, "#d5d8dc", True))
    for (bx, by), n in ((BOOT, "BOOT"), (RST, "RST")):
        piezas.append(caja_(n, "esp", X_ESP + bx - 1.5, Y_ESP + by - 1.5, ESP_ARRIBA, X_ESP + bx + 1.5, Y_ESP + by + 1.5,
                            ESP_ARRIBA + BOTON_ALTO, "#e8e8e8"))
    piezas.append(caja_("LED", "esp", X_ESP + LED[0] - 1, Y_ESP + LED[1] - 1, ESP_ARRIBA, X_ESP + LED[0] + 1, Y_ESP + LED[1] + 1,
                        ESP_ARRIBA + 0.8, "#ff3b6b"))
    if not plana:
        for yy in (FILA_BORDE, ESP_ANCHO - FILA_BORDE):
            piezas.append(caja_("Tira de pines", "esp", X_ESP + 0.2, Y_ESP + yy - 1.27, ESP_Z - ESPACIADOR, X_ESP + ESP_LARGO - 0.2,
                                Y_ESP + yy + 1.27, ESP_Z, "#e6c229"))
    # MAX3421E
    piezas.append(caja_("MAX3421E", "max", X_MAX, Y_MAX, MAX_Z, X_MAX + MAX_LARGO, Y_MAX + MAX_ANCHO, USBA_Z, "#1f4fa8"))
    x_usba = LARGO - X_USB - 15 if plana else X_USB
    piezas.append(caja_("USB-A (mando)", "max", x_usba, ANCHO / 2 - USBA_ANCHO / 2, USBA_Z, x_usba + 15, ANCHO / 2 + USBA_ANCHO / 2,
                        USBA_Z + USBA_ALTO, "#d5d8dc", True))
    xc = X_MAX + (8 if plana else MAX_LARGO - 14)
    piezas.append(caja_("Chip MAX3421E", "max", xc, ANCHO / 2 - 2.5, USBA_Z, xc + 5, ANCHO / 2 + 2.5, USBA_Z + 0.9, "#111"))
    piezas.append(caja_("Cristal", "max", xc + 7, ANCHO / 2 - 2, USBA_Z, xc + 10.5, ANCHO / 2 + 2, USBA_Z + 1.2, "#aaa", True))

    cables = []
    if VARIANTE != "conectable":
        y_esp = Y_ESP + ESP_ANCHO - FILA_BORDE
        y_max = Y_MAX + MAX_ANCHO - 1.3
        z_esp = ESP_Z - (0 if plana else ESPACIADOR + PIN_LARGO)
        orden = sorted(CABLES, key=lambda c: 22 - c[0])
        for k, (pin, texto, color) in enumerate(orden):
            x0 = X_ESP + PIN_PRIMERO + (22 - pin) * PIN_PASO
            # repartidos por el borde del MAX, lejos del USB-A (en la plana, el USB-A está al final del MAX)
            x1 = X_MAX + 3 + k * (MAX_LARGO - 9) / (len(orden) - 1) if plana else X_MAX + 16 + k * (MAX_LARGO - 19) / (len(orden) - 1)
            cables.append({"texto": texto, "color": color, "puntos": [
                [x0, y_esp, z_esp], [x0, y_esp + 0.3, z_esp - 1.2], [(x0 + x1) / 2, (y_esp + y_max) / 2 + 0.8, (z_esp + USBA_Z) / 2 + 0.6],
                [x1, y_max + 0.2, USBA_Z + 1.2], [x1, y_max, USBA_Z]]})

    datos = {
        "variante": VARIANTE, "medidas": [round(LARGO, 1), round(ANCHO, 1), round(ALTO_BASE + TAPA, 1)],
        "base": malla(base()), "tapa": malla(tapa().mirror((0, 0, 1)).translate((0, 0, ALTO_BASE + TAPA))),
        "piezas": piezas, "cables": cables, "centro": [LARGO / 2, ANCHO / 2, (ALTO_BASE + TAPA) / 2],
    }
    salida.write_text(PLANTILLA_VISOR.replace("__DATOS__", json.dumps(datos, separators=(",", ":"))), encoding="utf-8")


PLANTILLA_VISOR = r"""<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Caja del puente · visor 3D</title>
<style>
  :root { color-scheme: dark; }
  html, body { margin: 0; height: 100%; background: #0f1115; color: #e8e6e3; font: 14px/1.4 -apple-system, system-ui, sans-serif; overflow: hidden; }
  #panel { position: absolute; top: 14px; left: 14px; width: 270px; background: rgba(22,24,30,.92); border: 1px solid #2a2e37;
           border-radius: 12px; padding: 14px 16px; backdrop-filter: blur(6px); }
  h1 { font-size: 15px; margin: 0 0 2px; } .sub { color: #9aa0a6; font-size: 12px; margin-bottom: 12px; }
  label { display: flex; align-items: center; gap: 8px; margin: 7px 0; cursor: pointer; user-select: none; }
  input[type=range] { width: 100%; accent-color: #d97757; } input[type=checkbox] { accent-color: #d97757; }
  .fila { display: flex; gap: 6px; margin-top: 10px; flex-wrap: wrap; }
  button { background: #262a33; color: #e8e6e3; border: 1px solid #343944; border-radius: 8px; padding: 6px 9px; cursor: pointer; font: inherit; font-size: 12px; }
  button:hover { border-color: #d97757; }
  #leyenda { position: absolute; right: 14px; bottom: 14px; background: rgba(22,24,30,.92); border: 1px solid #2a2e37; border-radius: 12px;
             padding: 10px 14px; font-size: 12px; max-width: 260px; }
  #leyenda div { display: flex; align-items: center; gap: 8px; margin: 3px 0; } .c { width: 14px; height: 4px; border-radius: 2px; }
  #info { position: absolute; left: 50%; bottom: 14px; transform: translateX(-50%); background: rgba(22,24,30,.92); border: 1px solid #2a2e37;
          border-radius: 8px; padding: 6px 12px; font-size: 13px; pointer-events: none; opacity: 0; transition: opacity .15s; }
  .nota { color: #9aa0a6; font-size: 11.5px; margin-top: 10px; }
  .limpio #panel, .limpio #leyenda, .limpio #info { display: none; }
</style></head>
<body>
<div id="panel">
  <h1>Caja del puente</h1>
  <div class="sub" id="sub"></div>
  <div>Separar piezas</div><input id="separar" type="range" min="0" max="1" step="0.01" value="0">
  <label><input id="tapa" type="checkbox" checked> Tapa</label>
  <label><input id="caja" type="checkbox" checked> Caja</label>
  <label><input id="transp" type="checkbox"> Caja transparente</label>
  <label><input id="corte" type="checkbox"> Cortar por la mitad</label>
  <label><input id="cables" type="checkbox" checked> Cables</label>
  <div class="fila">
    <button data-vista="iso">3D</button><button data-vista="usbc">Cara USB-C</button><button data-vista="usba">Cara USB-A</button>
    <button data-vista="lado">Lado</button><button data-vista="arriba">Arriba</button>
  </div>
  <div class="nota">Arrastra para girar · rueda para acercar · clic derecho para mover. Pasa el ratón por una pieza para ver qué es.
  Las posiciones de los cables en el MAX son aproximadas.</div>
</div>
<div id="leyenda"></div>
<div id="info"></div>
<script type="importmap">{"imports":{"three":"https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js",
"three/addons/":"https://cdn.jsdelivr.net/npm/three@0.160.0/examples/jsm/"}}</script>
<script type="module">
import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
const D = __DATOS__;
const [L, A, H] = D.medidas;
document.getElementById("sub").textContent = `Variante ${D.variante} · ${String(L).replace(".", ",")} × ${String(A).replace(".", ",")} × ${String(H).replace(".", ",")} mm`;

const render = new THREE.WebGLRenderer({ antialias: true });
render.setPixelRatio(devicePixelRatio); render.setSize(innerWidth, innerHeight);
render.localClippingEnabled = true; render.shadowMap.enabled = true;
document.body.appendChild(render.domElement);
const escena = new THREE.Scene(); escena.background = new THREE.Color("#0f1115");
const cam = new THREE.PerspectiveCamera(35, innerWidth / innerHeight, 1, 2000); cam.up.set(0, 0, 1);
const ctl = new OrbitControls(cam, render.domElement); ctl.enableDamping = true;
const C = new THREE.Vector3(...D.centro); ctl.target.copy(C);

escena.add(new THREE.HemisphereLight("#ffffff", "#30343c", 1.6));
const sol = new THREE.DirectionalLight("#ffffff", 1.6); sol.position.set(-60, -90, 140); sol.castShadow = true;
sol.shadow.mapSize.set(2048, 2048); sol.shadow.bias = -0.0004; sol.shadow.normalBias = 0.08; Object.assign(sol.shadow.camera, { left: -80, right: 80, top: 80, bottom: -80 }); escena.add(sol);
const suelo = new THREE.Mesh(new THREE.PlaneGeometry(600, 600), new THREE.ShadowMaterial({ opacity: .35 }));
suelo.position.set(C.x, C.y, -0.05); suelo.receiveShadow = true; escena.add(suelo);
const rejilla = new THREE.GridHelper(300, 30, "#2a2e37", "#1b1e25"); rejilla.rotation.x = Math.PI / 2; rejilla.position.set(C.x, C.y, -0.04); escena.add(rejilla);

const corte = new THREE.Plane(new THREE.Vector3(0, 1, 0), -A / 2);   // quita la mitad delantera (y < A/2)
function geo(m) {
  let g = new THREE.BufferGeometry(); g.setAttribute("position", new THREE.Float32BufferAttribute(m.pos, 3)); g.setIndex(m.idx);
  g = g.toNonIndexed(); g.computeVertexNormals(); return g;   // caras planas: aristas nítidas
}
const matCaja = new THREE.MeshStandardMaterial({ color: "#d9d6cf", roughness: .7, side: THREE.DoubleSide });
const matTapa = new THREE.MeshStandardMaterial({ color: "#d97757", roughness: .6, side: THREE.DoubleSide });
const caja = new THREE.Mesh(geo(D.base), matCaja); caja.castShadow = caja.receiveShadow = true; caja.userData.nombre = "Caja (base)";
const tapa = new THREE.Mesh(geo(D.tapa), matTapa); tapa.castShadow = true; tapa.userData.nombre = "Tapa";
escena.add(caja, tapa);

const grupos = { esp: new THREE.Group(), max: new THREE.Group(), cables: new THREE.Group() };
Object.values(grupos).forEach(g => escena.add(g));
for (const p of D.piezas) {
  const [x0, y0, z0] = p.min, [x1, y1, z1] = p.max;
  const m = new THREE.Mesh(new THREE.BoxGeometry(x1 - x0, y1 - y0, z1 - z0),
    new THREE.MeshStandardMaterial({ color: p.color, roughness: p.metal ? .25 : .6, metalness: p.metal ? .85 : 0 }));
  m.position.set((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2); m.castShadow = m.receiveShadow = true; m.userData.nombre = p.nombre;
  grupos[p.grupo].add(m);
}
const ley = document.getElementById("leyenda");
if (D.cables.length) ley.innerHTML = "<b>Cables</b>"; else ley.style.display = "none";
for (const c of D.cables) {
  const curva = new THREE.CatmullRomCurve3(c.puntos.map(p => new THREE.Vector3(...p)));
  const t = new THREE.Mesh(new THREE.TubeGeometry(curva, 40, 0.35, 8), new THREE.MeshStandardMaterial({ color: c.color, roughness: .5 }));
  t.userData.nombre = "Cable " + c.texto; grupos.cables.add(t);
  ley.insertAdjacentHTML("beforeend", `<div><span class="c" style="background:${c.color}"></span>${c.texto}</div>`);
}

const $ = id => document.getElementById(id);
function actualizar() {
  const s = +$("separar").value;
  tapa.position.z = s * 30; grupos.esp.position.z = s * 16; grupos.max.position.z = s * 4;
  grupos.cables.visible = $("cables").checked && s === 0;
  tapa.visible = $("tapa").checked; caja.visible = $("caja").checked;
  const tr = $("transp").checked;
  for (const m of [matCaja, matTapa]) { m.transparent = tr; m.opacity = tr ? .28 : 1; m.depthWrite = !tr; m.clippingPlanes = $("corte").checked ? [corte] : []; m.needsUpdate = true; }
}
["separar", "tapa", "caja", "transp", "corte", "cables"].forEach(id => $(id).addEventListener("input", actualizar));

const vistas = { iso: [-1, -1.4, 1.1], usbc: [-1, 0, .25], usba: [1, 0, .25], lado: [0, -1, .15], arriba: [0, -.01, 1] };
function ir(n) { const d = new THREE.Vector3(...vistas[n]).normalize().multiplyScalar(170); cam.position.copy(C).add(d); ctl.target.copy(C); }
document.querySelectorAll("[data-vista]").forEach(b => b.onclick = () => ir(b.dataset.vista));
// estado inicial desde la dirección: visor.html#corte,transp,separar=0.6,vista=lado
for (const t of location.hash.slice(1).split(",").filter(Boolean)) {
  const [k, v] = t.split("=");
  if (k === "separar") $("separar").value = v; else if (k === "vista") vistas[v] && setTimeout(() => ir(v));
  else if (k === "limpio") {   // para capturas: sin paneles, fondo negro y tapa del color de la caja
    document.body.classList.add("limpio");
    escena.background = new THREE.Color("#000000"); matTapa.color.set("#c9c6bf"); rejilla.visible = false;
  }
  else if ($(k)) $(k).checked = !$(k).checked;
}
ir("iso"); actualizar();

const ray = new THREE.Raycaster(), ptr = new THREE.Vector2(), info = $("info");
addEventListener("pointermove", e => {
  ptr.set(e.clientX / innerWidth * 2 - 1, -e.clientY / innerHeight * 2 + 1); ray.setFromCamera(ptr, cam);
  const obj = [caja, tapa, ...grupos.esp.children, ...grupos.max.children, ...grupos.cables.children].filter(o => o.visible && o.parent.visible !== false);
  const hit = ray.intersectObjects(obj, false).find(h => !( $("corte").checked && (h.object === caja || h.object === tapa) && h.point.y < A / 2));
  info.style.opacity = hit ? 1 : 0; if (hit) info.textContent = hit.object.userData.nombre;
});
addEventListener("resize", () => { cam.aspect = innerWidth / innerHeight; cam.updateProjectionMatrix(); render.setSize(innerWidth, innerHeight); });
render.setAnimationLoop(() => { ctl.update(); render.render(escena, cam); });
</script></body></html>
"""


if __name__ == "__main__":
    aqui = Path(__file__).parent
    for v in ("conectable", "compacta", "plana"):
        configurar(v)
        d = aqui / v
        d.mkdir(exist_ok=True)
        a_stl(base(), d / "caja-base.stl")
        a_stl(tapa(), d / "caja-tapa.stl")
        a_stl(prueba_puertos(), d / "prueba-puertos.stl")
        print(f"{v}: {LARGO:.1f} × {ANCHO:.1f} × {ALTO_BASE + TAPA:.1f} mm (largo × ancho × alto)")
        if "--vistas" in sys.argv:
            vistas(d / "vistas.png")
        visor(d / "visor.html")
