"""Tablas de bibliotecas del proyecto (sym-lib-table, fp-lib-table) y el .kicad_pro.

Así el proyecto se abre igual en cualquier Mac con KiCad instalado en /Applications, sin configurar nada.
"""
import json
from pathlib import Path

from diseno import COMPONENTES
from sexpr import Q, escribir

KICAD = "/Applications/KiCad/KiCad.app/Contents/SharedSupport"
POTENCIA = ["VBUS", "VBUS_MANDO"]   # se trazan a 0,3 mm y luego se ensanchan a 0,6 donde caben (importar_rutas.py)
ALIMENTACION = ["+3V3", "LED_VDD"]  # 0,3 mm (la masa va por los planos)


def generar(carpeta: Path):
    libs_sim = sorted(({c["sym"].split(":")[0] for c in COMPONENTES} | {"power"}) - {"puente"})
    libs_fp = sorted({c["fp"].split(":")[0] for c in COMPONENTES})
    sim = "(sym_lib_table\n  (version 7)\n" + "".join(
        f'  (lib (name "{n}")(type "KiCad")(uri "{KICAD}/symbols/{n}.kicad_sym")(options "")(descr ""))\n'
        for n in libs_sim) + '  (lib (name "puente")(type "KiCad")(uri "${KIPRJMOD}/puente.kicad_sym")(options "")(descr ""))\n' + ")\n"
    fp = "(fp_lib_table\n  (version 7)\n" + "".join(
        f'  (lib (name "{n}")(type "KiCad")(uri "{KICAD}/footprints/{n}.pretty")(options "")(descr ""))\n'
        for n in libs_fp) + ")\n"
    (carpeta / "sym-lib-table").write_text(sim)
    (carpeta / "fp-lib-table").write_text(fp)
    # La biblioteca propia, con el MAX3421E (no está en las de KiCad)
    from esquema import _simbolo_max3421e
    sim_max = _simbolo_max3421e()
    sim_max[1] = Q("MAX3421E")
    (carpeta / "puente.kicad_sym").write_text(escribir(
        ["kicad_symbol_lib", ["version", "20251024"], ["generator", Q("placa/tablas.py")], sim_max]) + "\n")
    # Reglas de diseño (capacidades estándar de JLCPCB en 2 capas, con margen) y clases de red
    clase = lambda nombre, pista, via, taladro, prioridad: {
        "name": nombre, "clearance": 0.15, "track_width": pista, "via_diameter": via, "via_drill": taladro,
        "microvia_diameter": 0.3, "microvia_drill": 0.1, "diff_pair_gap": 0.25, "diff_pair_width": 0.2,
        "diff_pair_via_gap": 0.25, "wire_width": 6, "bus_width": 12, "line_style": 0, "priority": prioridad,
        "pcb_color": "rgba(0, 0, 0, 0.000)", "schematic_color": "rgba(0, 0, 0, 0.000)"}
    pro = {
        "meta": {"filename": "puente.kicad_pro", "version": 3},
        "board": {"design_settings": {"rules": {
            "min_clearance": 0.15, "min_track_width": 0.15, "min_copper_edge_clearance": 0.3,
            "min_via_diameter": 0.5, "min_via_annular_width": 0.1, "min_through_hole_diameter": 0.3,
            "min_hole_to_hole": 0.25, "min_hole_clearance": 0.25, "min_text_height": 0.8,
            "min_text_thickness": 0.08, "min_silk_clearance": 0.0, "min_microvia_diameter": 0.2,
            "min_microvia_drill": 0.1, "solder_mask_to_copper_clearance": 0.0}}},
        "net_settings": {
            "meta": {"version": 4},
            "classes": [clase("Default", 0.2, 0.6, 0.3, 2147483647), clase("Potencia", 0.3, 0.6, 0.3, 0),
                        clase("Alimentacion", 0.3, 0.6, 0.3, 1)],
            "netclass_patterns": [{"netclass": "Potencia", "pattern": f"/{n}"} for n in POTENCIA]
                                + [{"netclass": "Alimentacion", "pattern": f"/{n}"} for n in ALIMENTACION],
        },
    }
    (carpeta / "puente.kicad_pro").write_text(json.dumps(pro, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    generar(Path(__file__).parent)
