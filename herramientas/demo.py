#!/usr/bin/env python3
"""Genera la demo de la web (web/demo/index.html) con la página real de la app (app/Pagina.swift, la misma que sirven
la placa y las apps de Mac y escritorio) y le enlaza web/demo/simulador.js antes de su script: el simulador hace de
placa (contesta /perfil, /api, /eventos, /wifi… con el mismo JSON) para poder tocar la app sin tenerla.

Uso: herramientas/demo.py   (desde cualquier carpeta; no toca Pagina.swift ni nada de la app o el firmware)"""
import hashlib
import shutil
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
PAGINA = RAIZ / "app" / "Pagina.swift"
ICONO = RAIZ / "escritorio" / "src-tauri" / "icons" / "128x128@2x.png"   # el mismo que sirve la placa en /icono.png
DEMO = RAIZ / "web" / "demo"
SIMULADOR = DEMO / "simulador.js"


def cambiar(html, viejo, nuevo, veces):
    """Sustituye y comprueba que estaba exactamente esas veces (si la página cambia, mejor fallar que dejarla a medias)"""
    n = html.count(viejo)
    if n != veces:
        raise SystemExit(f"demo.py: esperaba {veces} vez/veces «{viejo}» en la página y hay {n}")
    return html.replace(viejo, nuevo)


def main():
    # Igual que herramientas/pagina.py
    texto = PAGINA.read_text(encoding="utf-8")
    marca = 'static let html = #"""\n'
    inicio = texto.index(marca) + len(marca)
    fin = texto.index('\n"""#', inicio)
    html = texto[inicio:fin]

    # La versión del simulador va en la dirección para que los navegadores no se queden con uno viejo
    version = hashlib.sha1(SIMULADOR.read_bytes()).hexdigest()[:10]
    html = cambiar(html, "<!doctype html>\n",
                   "<!doctype html>\n<!-- Generado por herramientas/demo.py a partir de app/Pagina.swift: no se edita a mano -->\n", 1)
    html = cambiar(html, "<title>p5k-ps5</title>", "<title>p5k-ps5 · demo</title>", 1)
    # El icono, desde la propia carpeta de la demo (en la placa está en la raíz)
    html = cambiar(html, 'href="/icono.png"', 'href="icono.png"', 2)
    # El simulador, antes del único script de la página
    html = cambiar(html, "<script>\n", f'<script src="simulador.js?v={version}"></script>\n<script>\n', 1)

    DEMO.mkdir(parents=True, exist_ok=True)
    (DEMO / "index.html").write_text(html, encoding="utf-8")
    shutil.copyfile(ICONO, DEMO / "icono.png")
    print(f"web/demo/index.html ({len(html.encode('utf-8')) // 1024} KB), simulador v={version}")


if __name__ == "__main__":
    main()
