// Código QR para la sección «Móvil» (la dirección con la clave), sin dependencias: modo byte, corrección M,
// versiones 1 a 10 (hasta 213 bytes; una dirección con la clave ocupa unos 40). Sigue la norma ISO/IEC 18004
// con la misma construcción que la biblioteca de referencia de Nayuki.

/// (codewords de corrección por bloque, [(bloques, datos por bloque); hasta 2 grupos]) del nivel M
const BLOQUES_M: [(usize, [(usize, usize); 2]); 10] = [
    (10, [(1, 16), (0, 0)]),
    (16, [(1, 28), (0, 0)]),
    (26, [(1, 44), (0, 0)]),
    (18, [(2, 32), (0, 0)]),
    (24, [(2, 43), (0, 0)]),
    (16, [(4, 27), (0, 0)]),
    (18, [(4, 31), (0, 0)]),
    (22, [(2, 38), (2, 39)]),
    (22, [(3, 36), (2, 37)]),
    (26, [(4, 43), (1, 44)]),
];

const ALINEACION: [&[i32]; 10] = [
    &[], &[6, 18], &[6, 22], &[6, 26], &[6, 30], &[6, 34], &[6, 22, 38], &[6, 24, 42], &[6, 26, 46], &[6, 28, 50],
];

struct Matriz {
    n: i32,
    m: Vec<bool>,
    funcion: Vec<bool>,
}

impl Matriz {
    fn get(&self, x: i32, y: i32) -> bool {
        self.m[(y * self.n + x) as usize]
    }
    fn fijar(&mut self, x: i32, y: i32, oscuro: bool) {
        let i = (y * self.n + x) as usize;
        self.m[i] = oscuro;
        self.funcion[i] = true;
    }
}

fn gf_mul(x: u32, y: u32) -> u32 {
    let mut z = 0u32;
    for i in (0..8).rev() {
        z = (z << 1) ^ ((z >> 7) * 0x11D);
        z ^= ((y >> i) & 1) * x;
    }
    z & 0xFF
}

fn divisor_rs(grado: usize) -> Vec<u32> {
    let mut r = vec![0u32; grado];
    r[grado - 1] = 1;
    let mut raiz = 1u32;
    for _ in 0..grado {
        for j in 0..grado {
            r[j] = gf_mul(r[j], raiz);
            if j + 1 < grado {
                r[j] ^= r[j + 1];
            }
        }
        raiz = gf_mul(raiz, 0x02);
    }
    r
}

fn resto_rs(datos: &[u8], divisor: &[u32]) -> Vec<u8> {
    let mut r = vec![0u32; divisor.len()];
    for &b in datos {
        let factor = b as u32 ^ r.remove(0);
        r.push(0);
        for (x, y) in r.iter_mut().zip(divisor) {
            *x ^= gf_mul(*y, factor);
        }
    }
    r.into_iter().map(|v| v as u8).collect()
}

/// La matriz del código (true = oscuro), o None si el texto no cabe
pub fn matriz(texto: &str) -> Option<(usize, Vec<bool>)> {
    let bytes = texto.as_bytes();
    // Versión: la más pequeña en la que caben modo (4 bits), longitud (8 o 16) y los datos
    let (version, (ecc, grupos)) = (1..=10).zip(BLOQUES_M.iter()).find(|(v, (_, g))| {
        let capacidad = g.iter().map(|(b, d)| b * d).sum::<usize>() * 8;
        let bits_long = if *v < 10 { 8 } else { 16 };
        4 + bits_long + bytes.len() * 8 <= capacidad
    })?;
    let capacidad = grupos.iter().map(|(b, d)| b * d).sum::<usize>();

    // Bits: modo byte, longitud, datos, terminador, relleno
    let mut bits: Vec<bool> = vec![];
    let poner = |valor: u32, n: u32, bits: &mut Vec<bool>| {
        for i in (0..n).rev() {
            bits.push((valor >> i) & 1 == 1);
        }
    };
    poner(0b0100, 4, &mut bits);
    poner(bytes.len() as u32, if version < 10 { 8 } else { 16 }, &mut bits);
    for &b in bytes {
        poner(b as u32, 8, &mut bits);
    }
    let tope = capacidad * 8;
    let terminador = (tope - bits.len()).min(4) as u32;
    poner(0, terminador, &mut bits);
    while bits.len() % 8 != 0 {
        bits.push(false);
    }
    let mut datos: Vec<u8> = bits.chunks(8).map(|c| c.iter().fold(0u8, |a, &b| (a << 1) | b as u8)).collect();
    let mut relleno = [0xEC, 0x11].iter().cycle();
    while datos.len() < capacidad {
        datos.push(*relleno.next().unwrap());
    }

    // Bloques con su corrección y entrelazado
    let divisor = divisor_rs(*ecc);
    let mut bloques: Vec<(Vec<u8>, Vec<u8>)> = vec![];
    let mut k = 0;
    for &(n, d) in grupos.iter() {
        for _ in 0..n {
            let trozo = datos[k..k + d].to_vec();
            k += d;
            let correccion = resto_rs(&trozo, &divisor);
            bloques.push((trozo, correccion));
        }
    }
    let mut final_: Vec<u8> = vec![];
    let max_datos = bloques.iter().map(|b| b.0.len()).max().unwrap_or(0);
    for i in 0..max_datos {
        for b in &bloques {
            if i < b.0.len() {
                final_.push(b.0[i]);
            }
        }
    }
    for i in 0..*ecc {
        for b in &bloques {
            final_.push(b.1[i]);
        }
    }

    // Patrones fijos
    let n = (version * 4 + 17) as i32;
    let mut q = Matriz { n, m: vec![false; (n * n) as usize], funcion: vec![false; (n * n) as usize] };
    for i in 0..n {
        q.fijar(6, i, i % 2 == 0);
        q.fijar(i, 6, i % 2 == 0);
    }
    for (cx, cy) in [(3, 3), (n - 4, 3), (3, n - 4)] {
        for dy in -4..=4 {
            for dx in -4..=4 {
                let (x, y) = (cx + dx, cy + dy);
                if (0..n).contains(&x) && (0..n).contains(&y) {
                    let dist = dx.abs().max(dy.abs());
                    q.fijar(x, y, dist != 2 && dist != 4);
                }
            }
        }
    }
    let pos = ALINEACION[version - 1];
    let ultimo = pos.len().saturating_sub(1);
    for i in 0..pos.len() {
        for j in 0..pos.len() {
            if (i == 0 && j == 0) || (i == 0 && j == ultimo) || (i == ultimo && j == 0) {
                continue;
            }
            for dy in -2..=2 {
                for dx in -2..=2 {
                    q.fijar(pos[i] + dx, pos[j] + dy, dx.abs().max(dy.abs()) != 1);
                }
            }
        }
    }
    formato(&mut q, 0); // reserva las zonas (se reescribe con la máscara elegida)
    if version >= 7 {
        let mut rem = version as u32;
        for _ in 0..12 {
            rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
        }
        let b = (version as u32) << 12 | rem;
        for i in 0..18 {
            let bit = (b >> i) & 1 == 1;
            let a = n - 11 + i % 3;
            let c = i / 3;
            q.fijar(a, c, bit);
            q.fijar(c, a, bit);
        }
    }

    // Datos en zigzag desde abajo a la derecha
    let mut i = 0usize;
    let mut derecha = n - 1;
    while derecha >= 1 {
        if derecha == 6 {
            derecha = 5;
        }
        for vert in 0..n {
            for j in 0..2 {
                let x = derecha - j;
                let arriba = ((derecha + 1) & 2) == 0;
                let y = if arriba { n - 1 - vert } else { vert };
                let idx = (y * n + x) as usize;
                if !q.funcion[idx] && i < final_.len() * 8 {
                    q.m[idx] = (final_[i >> 3] >> (7 - (i & 7))) & 1 == 1;
                    i += 1;
                }
            }
        }
        derecha -= 2;
    }

    // La máscara con menos penalización
    let mut mejor: Option<(i32, Vec<bool>)> = None;
    for mascara in 0..8 {
        let mut prueba = Matriz { n, m: q.m.clone(), funcion: q.funcion.clone() };
        aplicar_mascara(&mut prueba, mascara);
        formato(&mut prueba, mascara);
        let p = penalizacion(&prueba);
        if mejor.as_ref().is_none_or(|(mp, _)| p < *mp) {
            mejor = Some((p, prueba.m));
        }
    }
    Some((n as usize, mejor?.1))
}

fn formato(q: &mut Matriz, mascara: u32) {
    let datos = mascara; // nivel M = 00
    let mut rem = datos;
    for _ in 0..10 {
        rem = (rem << 1) ^ ((rem >> 9) * 0x537);
    }
    let bits = ((datos << 10) | rem) ^ 0x5412;
    let bit = |i: u32| (bits >> i) & 1 == 1;
    let n = q.n;
    for i in 0..=5 {
        q.fijar(8, i as i32, bit(i));
    }
    q.fijar(8, 7, bit(6));
    q.fijar(8, 8, bit(7));
    q.fijar(7, 8, bit(8));
    for i in 9..15 {
        q.fijar(14 - i as i32, 8, bit(i));
    }
    for i in 0..8 {
        q.fijar(n - 1 - i as i32, 8, bit(i));
    }
    for i in 8..15 {
        q.fijar(8, n - 15 + i as i32, bit(i));
    }
    q.fijar(8, n - 8, true); // el módulo oscuro fijo
}

fn aplicar_mascara(q: &mut Matriz, mascara: u32) {
    let n = q.n;
    for y in 0..n {
        for x in 0..n {
            let invertir = match mascara {
                0 => (x + y) % 2 == 0,
                1 => y % 2 == 0,
                2 => x % 3 == 0,
                3 => (x + y) % 3 == 0,
                4 => (x / 3 + y / 2) % 2 == 0,
                5 => x * y % 2 + x * y % 3 == 0,
                6 => (x * y % 2 + x * y % 3) % 2 == 0,
                _ => ((x + y) % 2 + x * y % 3) % 2 == 0,
            };
            let i = (y * n + x) as usize;
            if invertir && !q.funcion[i] {
                q.m[i] = !q.m[i];
            }
        }
    }
}

/// Penalización de la norma (rachas, bloques 2×2, patrones parecidos a los de esquina y proporción de oscuros)
fn penalizacion(q: &Matriz) -> i32 {
    let n = q.n;
    let mut p = 0;
    for horizontal in [true, false] {
        for a in 0..n {
            let celda = |b: i32| if horizontal { q.get(b, a) } else { q.get(a, b) };
            let mut racha = 1;
            for b in 1..n {
                if celda(b) == celda(b - 1) {
                    racha += 1;
                } else {
                    if racha >= 5 {
                        p += 3 + racha - 5;
                    }
                    racha = 1;
                }
            }
            if racha >= 5 {
                p += 3 + racha - 5;
            }
            let fila: Vec<bool> = (0..n).map(celda).collect();
            let patron = [true, false, true, true, true, false, true];
            for b in 0..=(n - 7) {
                if (0..7).all(|k| fila[(b + k) as usize] == patron[k as usize]) {
                    let antes = (b - 4..b).all(|k| k < 0 || !fila[k as usize]);
                    let despues = (b + 7..b + 11).all(|k| k >= n || !fila[k as usize]);
                    if antes || despues {
                        p += 40;
                    }
                }
            }
        }
    }
    for y in 0..n - 1 {
        for x in 0..n - 1 {
            let c = q.get(x, y);
            if c == q.get(x + 1, y) && c == q.get(x, y + 1) && c == q.get(x + 1, y + 1) {
                p += 3;
            }
        }
    }
    let oscuros = q.m.iter().filter(|&&v| v).count() as i32;
    let total = n * n;
    let k = ((oscuros * 20 - total * 10).abs() + total - 1) / total - 1;
    p + k.max(0) * 10
}

/// El código como SVG (con su margen blanco de 4 módulos), o None si no cabe
pub fn svg(texto: &str) -> Option<String> {
    let (n, m) = matriz(texto)?;
    let lado = n + 8;
    let mut camino = String::new();
    for y in 0..n {
        for x in 0..n {
            if m[y * n + x] {
                camino += &format!("M{},{}h1v1h-1z", x + 4, y + 4);
            }
        }
    }
    Some(format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 {lado} {lado}\" shape-rendering=\"crispEdges\"><rect width=\"{lado}\" height=\"{lado}\" fill=\"#fff\"/><path d=\"{camino}\" fill=\"#000\"/></svg>"
    ))
}

#[cfg(test)]
mod pruebas {
    #[test]
    fn genera_codigos_de_las_direcciones() {
        let (n, m) = super::matriz("http://192.168.1.20:8787/#k=ABCDEFGHJK").unwrap();
        assert_eq!(n, 29, "versión 3");
        assert_eq!(m.len(), n * n);
        // Las tres esquinas tienen el patrón de posición (oscuro en el borde y en el centro)
        assert!(m[0] && m[3 * n + 3] && m[n - 1] && m[(n - 1) * n]);
        assert!(super::svg(&"x".repeat(300)).is_none(), "lo que no cabe en la versión 10 no se genera");
        assert!(super::svg("http://10.0.0.5:8787/#k=ABCDEFGHJK").unwrap().starts_with("<svg"));
    }

    /// Escribe unos PNG en blanco y negro para comprobar con un lector de verdad (prueba ignorada)
    #[test]
    #[ignore]
    fn volcar_para_leer() {
        let dir = std::env::var("QR_DIR").unwrap_or_else(|_| std::env::temp_dir().to_string_lossy().to_string());
        for (i, t) in ["http://192.168.1.20:8787/#k=ABCDEFGHJK", "hola", &format!("http://192.168.100.200:8787/#k=ABCDEFGHJK&{}", "x".repeat(150))].iter().enumerate() {
            let (n, m) = super::matriz(t).unwrap();
            let escala = 8;
            let lado = (n + 8) * escala;
            // PGM (escala de grises), fácil de convertir
            let mut pgm = format!("P5 {lado} {lado} 255\n").into_bytes();
            for py in 0..lado {
                for px in 0..lado {
                    let (x, y) = ((px / escala) as i64 - 4, (py / escala) as i64 - 4);
                    let oscuro = x >= 0 && y >= 0 && (x as usize) < n && (y as usize) < n && m[y as usize * n + x as usize];
                    pgm.push(if oscuro { 0 } else { 255 });
                }
            }
            std::fs::write(format!("{dir}/qr{i}.pgm"), pgm).unwrap();
            std::fs::write(format!("{dir}/qr{i}.txt"), t).unwrap();
        }
    }
}
