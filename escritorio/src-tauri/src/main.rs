// En Windows no abre la ventana negra de la consola en la versión final.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    puente_de_mando_lib::ejecutar()
}
