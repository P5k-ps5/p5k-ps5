// La página del móvil es la misma que sirve la app de Mac: se saca de app/Pagina.swift al compilar
// (una sola fuente para las dos apps).
fn main() {
    let swift = "../../app/Pagina.swift";
    println!("cargo:rerun-if-changed={swift}");
    let texto = std::fs::read_to_string(swift).expect("no encuentro app/Pagina.swift");
    let inicio = texto.find("static let html = #\"\"\"\n").expect("falta el inicio de la página") + "static let html = #\"\"\"\n".len();
    let fin = texto[inicio..].find("\n\"\"\"#").expect("falta el final de la página") + inicio;
    let destino = std::path::Path::new(&std::env::var("OUT_DIR").unwrap()).join("pagina.html");
    std::fs::write(destino, &texto[inicio..fin]).unwrap();
    tauri_build::build()
}
