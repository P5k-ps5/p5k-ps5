#!/usr/bin/env python3
"""Saca la página web de app/Pagina.swift (la misma que sirven la app de Mac y la de escritorio) y la
comprime con gzip para meterla en el firmware de la placa. Uso: pagina.py Pagina.swift salida.html.gz"""
import gzip
import sys

texto = open(sys.argv[1], encoding="utf-8").read()
marca = 'static let html = #"""\n'
inicio = texto.index(marca) + len(marca)
fin = texto.index('\n"""#', inicio)
html = texto[inicio:fin].encode("utf-8")
with open(sys.argv[2], "wb") as f:
    f.write(gzip.compress(html, compresslevel=9, mtime=0))
