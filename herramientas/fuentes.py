#!/usr/bin/env python3
"""Prepara las fuentes de la interfaz (Inter Tight y Geist Mono, licencia OFL) a partir de las de NeuroClaude.

Saca un recorte con lo que hace falta para el español, para que la página pese poco dentro del firmware:
  app/fuentes/*.ttf            las que carga la app de Mac (construir_app.sh las copia a Resources)
  escritorio/ui/fuentes/*.woff2  las del instalador de escritorio
  app/Pagina.swift             las mismas woff2 en base64, entre las marcas FUENTES (la página no tiene internet)

Hace falta `pip install fonttools brotli`. Uso: fuentes.py [carpeta con las woff2 originales]"""
import base64
import os
import re
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ORIGEN = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Developer/cabina/web/fuentes")
TTF = os.path.join(RAIZ, "app/fuentes")
WOFF2 = os.path.join(RAIZ, "escritorio/ui/fuentes")
PAGINA = os.path.join(RAIZ, "app/Pagina.swift")

# Latín básico y Latin-1 (acentos, ñ, ¿, ¡, «, », ·), más la puntuación que sale en los textos
LETRAS = list(range(0x20, 0x7F)) + list(range(0xA0, 0x100)) + [0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2026, 0x20AC]


def recortar(fuente):
    o = subset.Options()
    o.layout_features = ["kern", "liga", "calt", "ccmp", "locl", "mark", "mkmk", "tnum"]
    o.name_IDs = [1, 2, 3, 4, 5, 6, 13, 14, 16, 17]  # 13 y 14: la licencia, que tiene que viajar con la fuente
    o.notdef_outline = True
    s = subset.Subsetter(o)
    s.populate(unicodes=LETRAS)
    s.subset(fuente)
    return fuente


def nombrar(fuente, familia, estilo):
    """Nombres fijos: SwiftUI pide la fuente por su nombre PostScript («InterTight-Medium»)."""
    ps = familia.replace(" ", "") + "-" + estilo
    nombres = fuente["name"]
    for id_, valor in ((1, f"{familia} {estilo}"), (2, "Regular"), (3, ps), (4, f"{familia} {estilo}"), (6, ps), (16, familia), (17, estilo)):
        nombres.setName(valor, id_, 3, 1, 0x409)


def guardar(fuente, ruta, formato):
    fuente.flavor = formato
    fuente.save(ruta)
    print(f"{os.path.relpath(ruta, RAIZ)}: {os.path.getsize(ruta) / 1024:.1f} KB")


os.makedirs(TTF, exist_ok=True)
os.makedirs(WOFF2, exist_ok=True)
inter = os.path.join(ORIGEN, "inter-tight-latin-wght-normal.woff2")

# La web: una sola variable de Inter Tight (300 a 600) y Geist Mono en sus dos pesos
guardar(instancer.instantiateVariableFont(recortar(TTFont(inter)), {"wght": (300, 600)}), os.path.join(WOFF2, "inter-tight.woff2"), "woff2")
for peso in (300, 400):
    guardar(recortar(TTFont(os.path.join(ORIGEN, f"geist-mono-latin-{peso}-normal.woff2"))), os.path.join(WOFF2, f"geist-mono-{peso}.woff2"), "woff2")

# La app de Mac: fuentes fijas, una por peso
for peso, estilo in ((400, "Regular"), (500, "Medium"), (600, "SemiBold")):
    f = instancer.instantiateVariableFont(recortar(TTFont(inter)), {"wght": peso})
    nombrar(f, "Inter Tight", estilo)
    guardar(f, os.path.join(TTF, f"InterTight-{estilo}.ttf"), None)
for peso, estilo in ((300, "Light"), (400, "Regular"), (500, "Medium")):
    f = recortar(TTFont(os.path.join(ORIGEN, f"geist-mono-latin-{peso}-normal.woff2")))
    nombrar(f, "Geist Mono", estilo)
    guardar(f, os.path.join(TTF, f"GeistMono-{estilo}.ttf"), None)


def b64(nombre):
    with open(os.path.join(WOFF2, nombre), "rb") as f:
        return base64.b64encode(f.read()).decode()


bloque = (
    "<!-- FUENTES: lo genera herramientas/fuentes.py; no se edita a mano -->\n<style>\n"
    f'@font-face{{font-family:"Inter Tight";font-weight:300 600;font-display:swap;src:url(data:font/woff2;base64,{b64("inter-tight.woff2")}) format("woff2")}}\n'
    f'@font-face{{font-family:"Geist Mono";font-weight:300;font-display:swap;src:url(data:font/woff2;base64,{b64("geist-mono-300.woff2")}) format("woff2")}}\n'
    f'@font-face{{font-family:"Geist Mono";font-weight:400;font-display:swap;src:url(data:font/woff2;base64,{b64("geist-mono-400.woff2")}) format("woff2")}}\n'
    "</style>\n<!-- /FUENTES -->\n"
)
with open(PAGINA, encoding="utf-8") as f:
    texto = f.read()
patron = re.compile(r"<!-- FUENTES:.*?<!-- /FUENTES -->\n", re.S)
if patron.search(texto):
    texto = patron.sub(lambda _: bloque, texto)
else:
    texto = texto.replace("</head>\n", bloque + "</head>\n", 1)
with open(PAGINA, "w", encoding="utf-8") as f:
    f.write(texto)
print(f"Pagina.swift: bloque de fuentes de {len(bloque) / 1024:.1f} KB")
