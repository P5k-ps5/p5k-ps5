// Lo que la app de Mac hace con el sistema y aquí se hace igual en Windows y en Mac: que el ordenador no se
// duerma ni apague la pantalla mientras la app está abierta (si se durmiera, la consola dejaría de recibir el
// mando), los sonidos de aviso y la hora local (para agrupar «Mi control» por días).

/// Mantiene el ordenador despierto mientras la app esté abierta
pub fn no_dormir() {
    #[cfg(target_os = "macos")]
    {
        // caffeinate se acaba solo cuando se cierra esta app (-w <pid>); -d pantalla, -i reposo, -m disco,
        // -s reposo enchufado (portátil cerrado con la pantalla en la PS5), -u «hay alguien»
        let pid = std::process::id().to_string();
        let _ = std::process::Command::new("caffeinate").args(["-dimsu", "-w", &pid]).spawn();
    }
    #[cfg(windows)]
    {
        use windows_sys::Win32::System::Power::{SetThreadExecutionState, ES_CONTINUOUS, ES_DISPLAY_REQUIRED, ES_SYSTEM_REQUIRED};
        // El estado vale mientras viva el hilo que lo pide: un hilo que no termina nunca
        std::thread::spawn(|| {
            unsafe { SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED) };
            loop {
                std::thread::sleep(std::time::Duration::from_secs(3600));
            }
        });
    }
}

/// Los sonidos que usa la app de Mac (NSSound)
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Sonido {
    /// Algo se enciende: anti-recoil, macro
    Glass,
    /// Algo se apaga: anti-recoil, macro
    Bottle,
    /// La ayuda al apuntado se enciende
    Ping,
    /// La ayuda al apuntado se apaga
    Funk,
    /// Cambio de perfil
    Pop,
    /// Ajuste desde el mando (fuerza, ajustes rápidos)
    Tink,
    /// Cambio de patrón de la ayuda
    Morse,
}

impl Sonido {
    #[cfg_attr(windows, allow(dead_code))]
    fn nombre(self) -> &'static str {
        match self {
            Sonido::Glass => "Glass", Sonido::Bottle => "Bottle", Sonido::Ping => "Ping", Sonido::Funk => "Funk",
            Sonido::Pop => "Pop", Sonido::Tink => "Tink", Sonido::Morse => "Morse",
        }
    }

    /// En Windows, los sonidos del sistema más parecidos (C:\Windows\Media)
    #[cfg_attr(not(windows), allow(dead_code))]
    fn archivo_windows(self) -> &'static str {
        match self {
            Sonido::Glass => "Windows Notify System Generic.wav",
            Sonido::Bottle => "Windows Background.wav",
            Sonido::Ping => "Windows Notify Messaging.wav",
            Sonido::Funk => "Windows Hardware Remove.wav",
            Sonido::Pop => "Windows Navigation Start.wav",
            Sonido::Tink => "Windows Ding.wav",
            Sonido::Morse => "Windows Notify Email.wav",
        }
    }
}

/// Suena sin bloquear (en el hilo del motor no se espera a nada)
pub fn sonar(s: Sonido) {
    #[cfg(target_os = "macos")]
    {
        let ruta = format!("/System/Library/Sounds/{}.aiff", s.nombre());
        let _ = std::process::Command::new("afplay").arg(ruta).spawn();
    }
    #[cfg(windows)]
    {
        use windows_sys::Win32::Media::Audio::{PlaySoundW, SND_ASYNC, SND_FILENAME, SND_NODEFAULT};
        let carpeta = std::env::var("SystemRoot").unwrap_or_else(|_| "C:\\Windows".into());
        let ruta = format!("{carpeta}\\Media\\{}", s.archivo_windows());
        let ancho: Vec<u16> = ruta.encode_utf16().chain(std::iter::once(0)).collect();
        // SND_ASYNC: vuelve enseguida; SND_NODEFAULT: si el archivo no existe, silencio (no el sonido por defecto)
        unsafe { PlaySoundW(ancho.as_ptr(), std::ptr::null_mut(), SND_FILENAME | SND_ASYNC | SND_NODEFAULT) };
    }
    #[cfg(not(any(target_os = "macos", windows)))]
    let _ = s.nombre();
}

/// Cuántos segundos han pasado desde las 0:00 de la hora local en el instante `unix` (segundos desde 1970)
pub fn segundos_del_dia_local(unix: f64) -> f64 {
    let entero = unix.floor();
    let fraccion = unix - entero;
    #[cfg(unix)]
    {
        let t = entero as libc::time_t;
        let mut tm: libc::tm = unsafe { std::mem::zeroed() };
        if unsafe { libc::localtime_r(&t, &mut tm) }.is_null() {
            return (unix.rem_euclid(86400.0)).max(0.0);
        }
        (tm.tm_hour as f64) * 3600.0 + (tm.tm_min as f64) * 60.0 + tm.tm_sec as f64 + fraccion
    }
    #[cfg(windows)]
    {
        use windows_sys::Win32::Foundation::{FILETIME, SYSTEMTIME};
        use windows_sys::Win32::System::Time::{FileTimeToSystemTime, SystemTimeToTzSpecificLocalTime};
        // FILETIME: intervalos de 100 ns desde 1601
        let ticks = ((entero + 11_644_473_600.0) * 10_000_000.0) as u64;
        let ft = FILETIME { dwLowDateTime: ticks as u32, dwHighDateTime: (ticks >> 32) as u32 };
        let mut utc: SYSTEMTIME = unsafe { std::mem::zeroed() };
        let mut local: SYSTEMTIME = unsafe { std::mem::zeroed() };
        let ok = unsafe { FileTimeToSystemTime(&ft, &mut utc) != 0 && SystemTimeToTzSpecificLocalTime(std::ptr::null(), &utc, &mut local) != 0 };
        if !ok {
            return unix.rem_euclid(86400.0);
        }
        (local.wHour as f64) * 3600.0 + (local.wMinute as f64) * 60.0 + local.wSecond as f64 + fraccion
    }
    #[cfg(not(any(unix, windows)))]
    {
        let _ = fraccion;
        unix.rem_euclid(86400.0)
    }
}

#[cfg(test)]
mod pruebas {
    #[test]
    fn hora_local_dentro_del_dia() {
        let ahora = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64();
        let s = super::segundos_del_dia_local(ahora);
        assert!((0.0..86400.0).contains(&s));
        // Un día después, la misma hora del día (salvo un cambio de horario de por medio)
        let manana = super::segundos_del_dia_local(ahora + 86400.0);
        assert!((s - manana).abs() < 1.0 || (s - manana).abs() == 3600.0 || ((s - manana).abs() - 3600.0).abs() < 1.0);
    }
}
