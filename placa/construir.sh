#!/bin/zsh
# Regenera la placa entera desde diseno.py: esquema, PCB, trazado, comprobaciones y archivos de fabricación.
# Necesita KiCad 10 en /Applications, Java (brew install openjdk) y Freerouting 2.5.0 en ~/.local/share/freerouting/.
set -e
cd "$(dirname "$0")"
PY=/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3.9
KC=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli
JAVA=/opt/homebrew/opt/openjdk/bin/java
FREEROUTING=~/.local/share/freerouting/freerouting-2.5.0.jar
silencio() { "$@" 2>&1 | grep -v -E "assert|memory leak|Debug: Adding duplicate" || true; }

python3 tablas.py
python3 esquema.py
silencio $PY pcb.py
silencio $PY importar_rutas.py dsn
$JAVA -jar $FREEROUTING -de puente.dsn -do puente.ses -mp 60 --gui.enabled=false 2>&1 \
  | grep -E "could not be routed|    - |Auto-routing stage completed" || true
silencio $PY importar_rutas.py ses
$KC sch erc -o /tmp/puente-erc.rpt puente.kicad_sch 2>&1 | grep infracc
$KC pcb drc --schematic-parity -o /tmp/puente-drc.rpt puente.kicad_pcb 2>&1 | grep -E "infracc|no conect|paridad"
grep -E "^\[" /tmp/puente-drc.rpt | sed -E 's/\]:.*/]/' | sort | uniq -c
python3 fabricacion.py
