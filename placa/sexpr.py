"""Lector y escritor mínimo de expresiones S de KiCad (bibliotecas de símbolos, esquemas)."""
import re


class Q(str):
    """Cadena que va entre comillas en el archivo"""


_TOKEN = re.compile(r'\s*(?:(\()|(\))|"((?:[^"\\]|\\.)*)"|([^\s()"]+))', re.S)


def leer(texto):
    pila = [[]]
    pos = 0
    while True:
        m = _TOKEN.match(texto, pos)
        if not m:
            break
        pos = m.end()
        abre, cierra, cadena, atomo = m.groups()
        if abre:
            pila.append([])
        elif cierra:
            nodo = pila.pop()
            pila[-1].append(nodo)
        elif cadena is not None:
            pila[-1].append(Q(cadena.replace('\\"', '"').replace("\\\\", "\\")))
        elif atomo is not None:
            pila[-1].append(atomo)
    return pila[0][0]


def escribir(nodo, nivel=0):
    if not isinstance(nodo, list):
        if isinstance(nodo, Q):
            return '"' + nodo.replace("\\", "\\\\").replace('"', '\\"') + '"'
        return str(nodo)
    simple = all(not isinstance(x, list) for x in nodo)
    if simple:
        return "(" + " ".join(escribir(x) for x in nodo) + ")"
    tab = "\t" * (nivel + 1)
    partes = []
    cabeza = []
    for x in nodo:
        if isinstance(x, list) or partes:
            partes.append(tab + escribir(x, nivel + 1))
        else:
            cabeza.append(escribir(x))
    return "(" + " ".join(cabeza) + "\n" + "\n".join(partes) + "\n" + "\t" * nivel + ")"


def hijos(nodo, nombre):
    return [x for x in nodo if isinstance(x, list) and x and x[0] == nombre]


def hijo(nodo, nombre):
    h = hijos(nodo, nombre)
    return h[0] if h else None
