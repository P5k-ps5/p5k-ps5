// El motor de la placa: el mismo código que la app de escritorio (perfiles, procesador, medidor, monitor,
// QR, informes del DualSense), compilado para el ESP32-S3 y enlazado con el firmware en C.
// Los archivos compartidos se incluyen tal cual desde escritorio/src-tauri/src: una sola fuente.

#[path = "../../../escritorio/src-tauri/src/modelo.rs"]
pub mod modelo;
#[allow(dead_code)]
#[path = "../../../escritorio/src-tauri/src/procesador.rs"]
pub mod procesador;
#[allow(dead_code)]
#[path = "../../../escritorio/src-tauri/src/medidor.rs"]
pub mod medidor;
#[allow(dead_code)]
#[path = "../../../escritorio/src-tauri/src/monitor.rs"]
pub mod monitor;
#[allow(dead_code)]
#[path = "../../../escritorio/src-tauri/src/qr.rs"]
pub mod qr;
#[allow(dead_code)]
#[path = "../../../escritorio/src-tauri/src/dualsense_informe.rs"]
pub mod dualsense_informe;

mod sistema;
pub mod nucleo;
mod ffi;
