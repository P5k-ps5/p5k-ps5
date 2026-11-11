// Lo poco del sistema que piden los archivos compartidos con el escritorio (en el escritorio está en
// escritorio/src-tauri/src/sistema.rs). En la placa, la hora local sale de la zona horaria de ESP-IDF (TZ).

/// Segundos desde la medianoche local de un instante (segundos desde 1970), para agrupar ráfagas por día
pub fn segundos_del_dia_local(unix: f64) -> f64 {
    let entero = unix.floor();
    let fraccion = unix - entero;
    let t = entero as libc::time_t;
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    if unsafe { libc::localtime_r(&t, &mut tm) }.is_null() {
        return unix.rem_euclid(86400.0).max(0.0);
    }
    (tm.tm_hour as f64) * 3600.0 + (tm.tm_min as f64) * 60.0 + tm.tm_sec as f64 + fraccion
}
