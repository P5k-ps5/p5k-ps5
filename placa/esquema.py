"""Genera el esquema (puente.kicad_sch) a partir de diseno.py.

Cada componente se coloca solo, y cada patilla lleva una etiqueta con el nombre de su red (las patillas libres,
una marca de «sin conectar»). No hay cables: dos patillas están unidas si sus etiquetas se llaman igual.
"""
import uuid
from pathlib import Path

from diseno import BANDERAS, COMPONENTES, MAX3421E_PINES
from sexpr import Q, escribir, hijo, hijos, leer

LIBS = Path("/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols")
PROYECTO = "puente"
_cache = {}


def _uid():
    return Q(str(uuid.uuid4()))


def _fuente(tam=1.27):
    return ["effects", ["font", ["size", str(tam), str(tam)]]]


# ---------------------------------------------------------------------------------------------------------
# Símbolos de biblioteca
# ---------------------------------------------------------------------------------------------------------
def _simbolo_de_biblioteca(lib, nombre):
    if lib not in _cache:
        _cache[lib] = {s[1]: s for s in hijos(leer((LIBS / f"{lib}.kicad_sym").read_text()), "symbol")}
    s = [list(x) if isinstance(x, list) else x for x in _cache[lib][nombre]]
    ext = hijo(s, "extends")
    if not ext:
        return s
    padre = _simbolo_de_biblioteca(lib, ext[1])
    propios = {p[1]: p for p in hijos(s, "property")}
    nuevo = [padre[0], Q(nombre)]
    for x in padre[2:]:
        if isinstance(x, list) and x[0] == "property":
            nuevo.append(propios.pop(x[1], x))
        elif isinstance(x, list) and x[0] == "symbol":
            nuevo.append([x[0], Q(x[1].replace(str(ext[1]), nombre, 1))] + x[2:])
        else:
            nuevo.append(x)
    nuevo[2:2] = list(propios.values())
    return nuevo


def _simbolo_max3421e():
    """El MAX3421E no está en las bibliotecas de KiCad: rectángulo con las 33 patillas (32 y la almohadilla EP)"""
    izq = [2, 23, 22, 24, 25, 12, 14, 13, 16, 15, 18, 17, 3, 19, 33, 21, 20]   # alimentación, cristal, SPI, GND, USB
    der = [4, 5, 6, 7, 8, 9, 10, 11, 26, 27, 28, 29, 30, 31, 32, 1]        # GPIO (no se usan)
    alto = 2.54 * 18
    pines = []
    for lado, lista in ((0, izq), (180, der)):
        for i, n in enumerate(lista):
            x = -17.78 if lado == 0 else 17.78
            y = alto / 2 - 2.54 * (i + 1)
            tipo = {"VCC": "power_in", "VL": "power_in", "GND": "power_in", "EP": "passive", "INT": "output", "MISO": "output",
                    "GPX": "output"}.get(MAX3421E_PINES[n], "bidirectional" if MAX3421E_PINES[n] in ("D+", "D-") else
                                         "output" if MAX3421E_PINES[n].startswith("GPOUT") else "input")
            pines.append(["pin", tipo, "line", ["at", f"{x:.2f}", f"{y:.2f}", str(lado)], ["length", "2.54"],
                          ["name", Q(MAX3421E_PINES[n]), _fuente()], ["number", Q(str(n)), _fuente()]])
    prop = lambda k, v, y, oculto=False: ["property", Q(k), Q(v), ["at", "0", f"{y:.2f}", "0"],
                                          _fuente() + ([["hide", "yes"]] if oculto else [])]
    return ["symbol", Q("puente:MAX3421E"), ["pin_names", ["offset", "1.016"]], ["exclude_from_sim", "no"],
            ["in_bom", "yes"], ["on_board", "yes"],
            prop("Reference", "U", alto / 2 + 1.27), prop("Value", "MAX3421E", -alto / 2 - 1.27),
            prop("Footprint", "Package_DFN_QFN:TQFN-32-1EP_5x5mm_P0.5mm_EP3.1x3.1mm", 0, True),
            prop("Datasheet", "https://www.analog.com/media/en/technical-documentation/data-sheets/MAX3421E.pdf", 0, True),
            prop("Description", "USB peripheral/host controller with SPI interface", 0, True),
            ["symbol", Q("MAX3421E_0_1"),
             ["rectangle", ["start", "-15.24", f"{alto / 2:.2f}"], ["end", "15.24", f"{-alto / 2:.2f}"],
              ["stroke", ["width", "0.254"], ["type", "default"]], ["fill", ["type", "background"]]]],
            ["symbol", Q("MAX3421E_1_1")] + pines]


def simbolo(lib_id):
    if lib_id == "puente:MAX3421E":
        s = _simbolo_max3421e()
    else:
        lib, nombre = lib_id.split(":")
        s = _simbolo_de_biblioteca(lib, nombre)
        s = [s[0], Q(lib_id)] + s[2:]
    return s


def pines(sim):
    """[(número, nombre, x, y, ángulo)] de la unidad 1 (o común) y estilo de cuerpo 1"""
    res = []
    for sub in hijos(sim, "symbol"):
        unidad, estilo = sub[1].rsplit("_", 2)[-2:]
        if unidad not in ("0", "1") or estilo not in ("0", "1"):
            continue
        for p in hijos(sub, "pin"):
            at = hijo(p, "at")
            res.append((str(hijo(p, "number")[1]), str(hijo(p, "name")[1]), float(at[1]), float(at[2]),
                        int(float(at[3])) if len(at) > 3 else 0))
    return res


# ---------------------------------------------------------------------------------------------------------
# Esquema
# ---------------------------------------------------------------------------------------------------------
def _etiqueta(red, x, y, angulo_pin):
    rot = {0: 180, 180: 0, 90: 270, 270: 90}[angulo_pin % 360]
    just = "right" if rot in (180, 270) else "left"
    return ["label", Q(red), ["at", f"{x:.2f}", f"{y:.2f}", str(rot)], _fuente() + [["justify", just, "bottom"]],
            ["uuid", _uid()]]


def _instancia(lib_id, ref, valor, fp, lcsc, x, y, pines_sim, raiz, dnp=False, ref_oculta=False):
    xs = [p[2] for p in pines_sim] or [0]
    ys = [-p[3] for p in pines_sim] or [0]
    arriba, abajo = min(ys) - 2.54, max(ys) + 2.54
    props = [("Reference", ref, y + arriba - 1.27, ref_oculta), ("Value", valor, y + abajo + 1.27, False),
             ("Footprint", fp, y, True), ("Datasheet", "", y, True), ("Description", "", y, True),
             ("LCSC", lcsc, y, True)]
    nodo = ["symbol", ["lib_id", Q(lib_id)], ["at", f"{x:.2f}", f"{y:.2f}", "0"], ["unit", "1"],
            ["exclude_from_sim", "no"], ["in_bom", "no" if dnp else "yes"], ["on_board", "yes"],
            ["dnp", "yes" if dnp else "no"], ["uuid", _uid()]]
    for k, v, py, oculto in props:
        nodo.append(["property", Q(k), Q(v), ["at", f"{x:.2f}", f"{py:.2f}", "0"],
                     _fuente() + ([["hide", "yes"]] if oculto else [])])
    for num in sorted({p[0] for p in pines_sim}):
        nodo.append(["pin", Q(num), ["uuid", _uid()]])
    nodo.append(["instances", ["project", Q(PROYECTO), ["path", Q("/" + raiz), ["reference", Q(ref)], ["unit", "1"]]]])
    return nodo


def generar(destino: Path):
    raiz = str(uuid.uuid4())
    lib_symbols = {}
    elementos = []

    lista = [dict(c) for c in COMPONENTES]
    for i, red in enumerate(BANDERAS, 1):
        lista.append(dict(ref=f"#FLG0{i}", sym="power:PWR_FLAG", valor="PWR_FLAG", fp="", lcsc="",
                          pines={"1": red}, bandera=True))

    # Colocación por filas (de izquierda a derecha y de arriba abajo), en una hoja A2 (594 x 420 mm)
    x0, y0, ancho_hoja = 20.32, 30.48, 560.0
    x, y, alto_fila = x0, y0, 0.0
    for c in lista:
        if c["sym"] not in lib_symbols:
            lib_symbols[c["sym"]] = simbolo(c["sym"])
        ps = pines(lib_symbols[c["sym"]])
        largo = max([len(c["pines"].get(p[0], "")) for p in ps] + [3]) * 1.0 + 4
        xs = [p[2] for p in ps]
        ys = [-p[3] for p in ps]
        izq = -min(xs) + (largo if any(p[4] == 0 for p in ps) else 4)
        der = max(xs) + (largo if any(p[4] == 180 for p in ps) else 4)
        sup = -min(ys) + (largo if any(p[4] == 270 for p in ps) else 6)
        inf = max(ys) + (largo if any(p[4] == 90 for p in ps) else 6)
        w, h = izq + der + 5.08, sup + inf + 5.08
        if x + w > ancho_hoja:
            x, y, alto_fila = x0, y + alto_fila, 0.0
        ox = round((x + izq) / 2.54) * 2.54
        oy = round((y + sup) / 2.54) * 2.54
        x += w
        alto_fila = max(alto_fila, h)

        elementos.append(_instancia(c["sym"], c["ref"], c["valor"], c["fp"], c["lcsc"], ox, oy, ps, raiz,
                                    dnp=c.get("dnp", False), ref_oculta=c.get("bandera", False)))
        for num, nombre, px, py, ang in ps:
            sx, sy = ox + px, oy - py
            red = c["pines"].get(num)
            if red:
                elementos.append(_etiqueta(red, sx, sy, ang))
            else:
                elementos.append(["no_connect", ["at", f"{sx:.2f}", f"{sy:.2f}"], ["uuid", _uid()]])

    doc = ["kicad_sch", ["version", "20250114"], ["generator", Q("eeschema")], ["generator_version", Q("9.0")],
           ["uuid", Q(raiz)], ["paper", Q("A2")],
           ["title_block", ["title", Q("Puente de mando: ESP32-S3 + MAX3421E")], ["rev", Q("1")],
            ["comment", "1", Q("Generado por placa/esquema.py a partir de placa/diseno.py: no editar a mano")]],
           ["lib_symbols"] + list(lib_symbols.values())] + elementos + \
          [["sheet_instances", ["path", Q("/"), ["page", Q("1")]]], ["embedded_fonts", "no"]]
    destino.write_text(escribir(doc) + "\n")
    return lib_symbols


if __name__ == "__main__":
    aqui = Path(__file__).parent
    generar(aqui / "puente.kicad_sch")
    print("Esquema:", aqui / "puente.kicad_sch")
