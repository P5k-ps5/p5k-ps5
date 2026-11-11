// p5k-ps5 (escritorio, Windows y Mac): el puente entero (DualSense → perfil → ESP32), el servidor
// del móvil y el iPad, y el asistente que graba el firmware en la placa y lleva a la compra del P5Mate.
mod dualsense;
mod dualsense_informe;
mod esp32;
mod medidor;
mod modelo;
mod modo;
mod monitor;
mod nucleo;
mod placa;
mod procesador;
mod qr;
mod servidor;
mod sincro;
mod sistema;

use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use tauri::menu::{Menu, MenuItem, Submenu};
use tauri::{Manager, State, Url};
use tauri_plugin_opener::OpenerExt;

use nucleo::Nucleo;
use servidor::Servidor;

/// Página del P5Mate. Es una constante a propósito: la interfaz no puede abrir otras direcciones.
const URL_P5MATE: &str = "https://www.amazon.es/dp/B0G4CXC69B?ref=ppx_yo2ov_dt_b_fed_asin_title";

struct Puente {
    nucleo: Arc<Nucleo>,
    servidor: Arc<Servidor>,
    /// Dirección del asistente (las páginas propias de la app) para volver a él desde el panel
    inicio: Mutex<Option<Url>>,
}

impl Puente {
    /// El panel es la misma página que el móvil, servida en este ordenador
    fn direccion_panel(&self) -> Result<String, String> {
        let limite = Instant::now() + Duration::from_secs(8);
        loop {
            if let Some(p) = *self.servidor.puerto.lock().unwrap() {
                return Ok(format!("http://127.0.0.1:{p}/#k={}", self.nucleo.clave()));
            }
            if Instant::now() > limite {
                return Err("El servidor del panel no arranca: ¿hay otra copia de la app abierta?".into());
            }
            std::thread::sleep(Duration::from_millis(100));
        }
    }

    /// Mientras se usa la placa desde el asistente, el motor la suelta y la vuelve a coger después
    fn con_placa_libre<R>(&self, f: impl FnOnce() -> R) -> R {
        self.nucleo.soltar_placa.store(true, Ordering::Relaxed);
        std::thread::sleep(Duration::from_millis(300));
        let r = f();
        self.nucleo.soltar_placa.store(std::env::var_os("PUENTE_SIN_PLACA").is_some(), Ordering::Relaxed);
        r
    }
}

#[tauri::command]
fn abrir_p5mate(app: tauri::AppHandle) -> Result<(), String> {
    app.opener()
        .open_url(URL_P5MATE, None::<&str>)
        .map_err(|e| format!("No he podido abrir el navegador: {e}"))
}

#[tauri::command]
fn listar_puertos() -> Vec<placa::Puerto> {
    placa::listar()
}

#[tauri::command]
fn info_firmware() -> placa::InfoFirmware {
    placa::info_firmware()
}

#[tauri::command]
async fn instalar_firmware(app: tauri::AppHandle, puerto: String) -> Result<placa::Resultado, String> {
    // Grabar bloquea durante varios segundos: fuera del hilo de la ventana.
    tauri::async_runtime::spawn_blocking(move || {
        let puente = app.state::<Puente>();
        puente.con_placa_libre(|| placa::instalar(&app, &puerto))
    })
    .await
    .map_err(|e| format!("La grabación se ha interrumpido: {e}"))?
}

#[tauri::command]
async fn detectar_modo() -> Result<modo::Modo, String> {
    tauri::async_runtime::spawn_blocking(modo::detectar)
        .await
        .map_err(|e| format!("No he podido buscar la placa: {e}"))
}

#[tauri::command]
async fn preguntar_modo(app: tauri::AppHandle, puerto: String) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let puente = app.state::<Puente>();
        puente.con_placa_libre(|| modo::preguntar(&puerto))
    })
    .await
    .map_err(|e| format!("No he podido preguntar a la placa: {e}"))?
}

#[tauri::command]
fn direccion_panel(puente: State<Puente>) -> Result<String, String> {
    puente.direccion_panel()
}

/// Direcciones para abrir el panel desde el móvil o el iPad (misma wifi)
#[tauri::command]
fn direcciones_movil(puente: State<Puente>) -> Vec<String> {
    let p = puente.servidor.puerto.lock().unwrap().unwrap_or(servidor::PUERTO);
    servidor::direcciones(p, &puente.nucleo.clave())
}

fn ir(app: &tauri::AppHandle, destino: &str) {
    let Some(ventana) = app.get_webview_window("main") else { return };
    let puente = app.state::<Puente>();
    let url = match destino {
        "panel" => puente.direccion_panel().ok().and_then(|u| Url::parse(&u).ok()),
        hash => puente.inicio.lock().unwrap().clone().map(|mut u| {
            u.set_fragment(Some(hash));
            u
        }),
    };
    if let Some(u) = url {
        let _ = ventana.navigate(u);
    }
}

pub fn ejecutar() {
    let nucleo = Nucleo::arrancar();
    let servidor = Servidor::arrancar(nucleo.clone());
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .manage(Puente { nucleo, servidor, inicio: Mutex::new(None) })
        .setup(|app| {
            if let Some(ventana) = app.get_webview_window("main") {
                let _ = ventana.set_title("p5k-ps5");
                *app.state::<Puente>().inicio.lock().unwrap() = ventana.url().ok();
            }
            // Menú: el panel, el asistente del firmware, la dirección para el móvil y la compra del P5Mate
            let panel = MenuItem::with_id(app, "panel", "Panel", true, Some("CmdOrCtrl+1"))?;
            let firmware = MenuItem::with_id(app, "firmware", "Instalar el firmware…", true, None::<&str>)?;
            let movil = MenuItem::with_id(app, "movil", "Abrir en el móvil o el iPad…", true, None::<&str>)?;
            let p5mate = MenuItem::with_id(app, "p5mate", "Comprar el P5Mate", true, None::<&str>)?;
            let puente = Submenu::with_items(app, "Puente", true, &[&panel, &firmware, &movil, &p5mate])?;
            let menu = Menu::default(app.handle())?;
            menu.append(&puente)?;
            app.set_menu(menu)?;
            app.on_menu_event(|app, ev| match ev.id().as_ref() {
                "panel" => ir(app, "panel"),
                "firmware" => ir(app, "placa"),
                "movil" => ir(app, "listo"),
                "p5mate" => {
                    let _ = app.opener().open_url(URL_P5MATE, None::<&str>);
                }
                _ => {}
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            abrir_p5mate,
            listar_puertos,
            info_firmware,
            instalar_firmware,
            detectar_modo,
            preguntar_modo,
            direccion_panel,
            direcciones_movil
        ])
        .build(tauri::generate_context!())
        .expect("error al arrancar la app")
        .run(|app, ev| {
            // Al cerrar, que la consola no se quede con nada pulsado y que se guarde todo
            if let tauri::RunEvent::Exit = ev {
                let puente = app.state::<Puente>();
                puente.nucleo.poner_pausa(true);
                std::thread::sleep(Duration::from_millis(80));
                puente.nucleo.almacen.lock().unwrap().guardar_ahora();
            }
        });
}
