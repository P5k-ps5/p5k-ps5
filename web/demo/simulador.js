// Simulador de la placa para la demo de la web (web/demo). Lo enlaza herramientas/demo.py antes del script de la
// página (la misma de app/Pagina.swift, sin tocarla) y sustituye fetch, EventSource y XMLHttpRequest para las rutas
// del servidor de la placa (main/web.c, contrato en PLACA-WEB.md). Contesta con el mismo JSON que el motor
// (components/motor/src/nucleo.rs) y aplica los cambios con la misma lógica (escritorio/src-tauri/src/modelo.rs,
// procesador.rs, medidor.rs y monitor.rs, portados aquí): un DualSense simulado juega solo y la página ve lo que
// recibiría la consola. Todo vive en memoria: al recargar, vuelve al estado inicial.
(() => {
"use strict";

// Dentro de la web (iframe), scrollIntoView movería también la página de fuera: aquí solo se desplaza
// el contenedor que se pueda desplazar dentro de la demo (la fila de pestañas, sobre todo).
if (window.top !== window) {
  Element.prototype.scrollIntoView = function () {
    for (let p = this.parentElement; p; p = p.parentElement) {
      if (p.scrollWidth > p.clientWidth + 1) {
        const izq = this.offsetLeft - p.offsetLeft, der = izq + this.offsetWidth;
        if (izq < p.scrollLeft) p.scrollLeft = izq - 8;
        else if (der > p.scrollLeft + p.clientWidth) p.scrollLeft = der - p.clientWidth + 8;
      }
      if (p.scrollHeight > p.clientHeight + 1 && p !== document.documentElement && p !== document.body) {
        const arr = this.offsetTop - p.offsetTop, aba = arr + this.offsetHeight;
        if (arr < p.scrollTop) p.scrollTop = arr - 8;
        else if (aba > p.scrollTop + p.clientHeight) p.scrollTop = aba - p.clientHeight + 8;
      }
    }
  };
}

const CLAVE = "DEMO";
const demoNo = que => "En la demo no se puede " + que + ": hace falta la placa.";

// ---------- Botones (modelo.rs: Boton) ----------
const BOTONES = ["cuadrado", "x", "circulo", "triangulo", "l1", "r1", "l2", "r2", "share", "options", "l3", "r3", "ps",
  "tactil", "arriba", "derecha", "abajo", "izquierda", "silenciar"];
const CORTO = {cuadrado: "□", x: "✕", circulo: "○", triangulo: "△", l1: "L1", r1: "R1", l2: "L2", r2: "R2", share: "Create",
  options: "Opt", l3: "L3", r3: "R3", ps: "PS", tactil: "Táctil", arriba: "↑", derecha: "→", abajo: "↓", izquierda: "←",
  silenciar: "Mic"};
const bit = b => 1 << BOTONES.indexOf(b);
const pulsado = (e, b) => (e.botones & bit(b)) !== 0;
const TIPOS = ["antiRecoil", "ayuda", "pausa", "turbos", "turbo", "macros", "macro"];
const COLORES = ["#0050FF", "#FF2D2D", "#00C853", "#FFB300", "#B000FF", "#00E5FF", "#FF4FA3", "#FFFFFF"];
const PATRONES = [
  ["Círculos discretos", "circulo", 4, 8, 300, 85], ["Círculos medios", "circulo", 8, 12, 150, 70],
  ["Círculos fuertes", "circulo", 14, 16, 80, 50], ["Temblor discreto", "temblor", 4, 8, 300, 85],
  ["Temblor medio", "temblor", 8, 12, 150, 70], ["Temblor fuerte", "temblor", 14, 16, 80, 50],
].map(([nombre, forma, tamano, hz, entradaMs, ceder]) => ({nombre, forma, tamano, hz, entradaMs, ceder}));

// min y max de Swift (procesador.rs: swift_min, swift_max)
const smin = (a, b) => (b < a ? b : a);
const smax = (a, b) => (b > a ? b : a);
// f64::round de Rust (la mitad, lejos del cero)
const redondear = v => (v < 0 ? -Math.round(-v) : Math.round(v));
const r3 = v => redondear(v * 1000) / 1000;
const clon = x => JSON.parse(JSON.stringify(x));

function nuevoId() {
  const h = "0123456789ABCDEF";
  let s = "";
  for (let i = 0; i < 36; i++) {
    if (i === 8 || i === 13 || i === 18 || i === 23) { s += "-"; continue; }
    if (i === 14) { s += "4"; continue; }
    let r = Math.random() * 16 | 0;
    if (i === 19) r = (r & 3) | 8;
    s += h[r];
  }
  return s;
}

// ---------- Esquemas: el mismo JSON que serde (orden de campos, valores por defecto, tipos) ----------
// n = f64, i = i64, b = bool, s = String, B = Boton, F = Forma, W = TipoWidget, map = BTreeMap<String, String>,
// ?s = Option<String> (no se escribe si está vacío), @x = otro esquema, [t] = lista
const E = {};
function esquema(nombre, def, campos) {
  E[nombre] = {def, campos: campos.trim().split(/\s+/).map(c => { const i = c.indexOf(":"); return [c.slice(0, i), c.slice(i + 1)]; })};
}
class NoValido extends Error {}
function leer(t, v) {
  if (t[0] === "@") return leerObj(E[t.slice(1)], v);
  if (t[0] === "[") {
    if (!Array.isArray(v)) throw new NoValido();
    return v.map(x => leer(t.slice(1, -1), x));
  }
  switch (t) {
    case "n": if (typeof v !== "number" || !isFinite(v)) throw new NoValido(); return v;
    case "i": if (!Number.isInteger(v)) throw new NoValido(); return v;
    case "b": if (typeof v !== "boolean") throw new NoValido(); return v;
    case "s": if (typeof v !== "string") throw new NoValido(); return v;
    case "B": if (!BOTONES.includes(v)) throw new NoValido(); return v;
    case "F": if (v !== "circulo" && v !== "temblor") throw new NoValido(); return v;
    case "W": if (!TIPOS.includes(v)) throw new NoValido(); return v;
    case "map": {
      if (!v || typeof v !== "object" || Array.isArray(v)) throw new NoValido();
      const o = {};
      for (const k of Object.keys(v).sort()) { if (typeof v[k] !== "string") throw new NoValido(); o[k] = v[k]; }
      return o;
    }
  }
  throw new NoValido();
}
function leerObj(e, v) {
  if (!v || typeof v !== "object" || Array.isArray(v)) throw new NoValido();
  const d = e.def(), o = {}, tiene = k => Object.prototype.hasOwnProperty.call(v, k);
  for (const [k, t] of e.campos) {
    if (t === "?s") {
      const x = tiene(k) ? v[k] : d[k];
      if (x === undefined || x === null) continue;
      if (typeof x !== "string") throw new NoValido();
      o[k] = x;
      continue;
    }
    o[k] = tiene(k) ? leer(t, v[k]) : d[k];
  }
  return o;
}
const nuevo = (nombre, v) => leerObj(E[nombre], v || {});

esquema("stick", () => ({zonaMuerta: 5, formaCruz: false, zonaExterna: 100, antiZonaMuerta: 0, curva: 1, sensX: 100, sensY: 100,
  limite: 100, suavizado: 0, aceleracion: 0, tiempoAceleracion: 300, invertirX: false, invertirY: false}),
  "zonaMuerta:n formaCruz:b zonaExterna:n antiZonaMuerta:n curva:n sensX:n sensY:n limite:n suavizado:n aceleracion:n tiempoAceleracion:n invertirX:b invertirY:b");
esquema("gatillo", () => ({zonaMuerta: 0, zonaExterna: 100, curva: 1, disparoRapido: false}),
  "zonaMuerta:n zonaExterna:n curva:n disparoRapido:b");
esquema("turbo", () => ({id: nuevoId(), boton: "x", hz: 10, ciclo: 50, activo: true}), "id:s boton:B hz:n ciclo:n activo:b");
esquema("paso", () => ({id: nuevoId(), botones: [], ms: 100}), "id:s botones:[B] ms:i");
esquema("macro", () => ({id: nuevoId(), nombre: "Macro nueva", activa: true, disparador: "r3", repetir: false,
  bloquearDisparador: true, pasos: [nuevo("paso", {botones: ["x"]}), nuevo("paso")], atajo: false, atajoMantener: "l1",
  atajoPulsar: "derecha"}),
  "id:s nombre:s activa:b disparador:B repetir:b bloquearDisparador:b pasos:[@paso] atajo:b atajoMantener:B atajoPulsar:B");
esquema("widget", () => ({id: nuevoId(), tipo: "antiRecoil"}), "id:s tipo:W objetivo:?s");
esquema("antiRecoil", () => ({activo: false, vertical: 20, progresivo: false, verticalFinal: 10, transicionMs: 1000, horizontal: 0,
  retardoMs: 0, disparar: "r2", apuntar: "l2", soloApuntando: true, atajo: true, atajoMantener: "l2", atajoPulsar: "abajo"}),
  "activo:b vertical:n progresivo:b verticalFinal:n transicionMs:n horizontal:n retardoMs:n disparar:B apuntar:B soloApuntando:b atajo:b atajoMantener:B atajoPulsar:B");
esquema("limites", () => ({activos: false, tamanoMin: 1, tamanoMax: 30, hzMin: 2, hzMax: 40, entradaMin: 0, entradaMax: 600}),
  "activos:b tamanoMin:n tamanoMax:n hzMin:n hzMax:n entradaMin:n entradaMax:n");
esquema("variante", () => ({id: nuevoId(), nombre: "Variante", base: -1, forma: "circulo", tamano: 8, hz: 12, entradaMs: 150, ceder: 70}),
  "id:s nombre:s base:i forma:F tamano:n hz:n entradaMs:n ceder:n");
esquema("ayuda", () => ({activo: false, forma: "circulo", tamano: 8, hz: 12, entradaMs: 150, ceder: 70, boton: "l2",
  tambienDisparando: false, atajo: true, atajoMantener: "l2", atajoPulsar: "arriba", cambioActivo: true, cambioMantener: "l1",
  cambioSiguiente: "derecha", cambioAnterior: "izquierda", limites: nuevo("limites"), variantes: []}),
  "activo:b forma:F tamano:n hz:n entradaMs:n ceder:n boton:B tambienDisparando:b atajo:b atajoMantener:B atajoPulsar:B cambioActivo:b cambioMantener:B cambioSiguiente:B cambioAnterior:B limites:@limites variantes:[@variante] varianteActiva:?s");
esquema("perfil", () => ({id: nuevoId(), nombre: "Perfil", intercambiarSticks: false, izq: nuevo("stick"), der: nuevo("stick"),
  l2: nuevo("gatillo"), r2: nuevo("gatillo"), reasignar: {}, alternar: [], pulsacionLarga: {}, msLarga: 300, turbos: [], macros: [],
  antiRecoil: nuevo("antiRecoil"), ayuda: nuevo("ayuda"), widgets: [], color: "#0050FF", enCiclo: true}),
  "id:s nombre:s intercambiarSticks:b izq:@stick der:@stick l2:@gatillo r2:@gatillo reasignar:map alternar:[B] pulsacionLarga:map msLarga:n turbos:[@turbo] macros:[@macro] antiRecoil:@antiRecoil ayuda:@ayuda widgets:[@widget] color:s enCiclo:b");
esquema("monitor", () => ({activo: false, maxAbs: 1, maxSalto: 0.3, maxVelocidad: 25, maxAceleracion: 4000, maxCambiosSigno: 0.6}),
  "activo:b maxAbs:n maxSalto:n maxVelocidad:n maxAceleracion:n maxCambiosSigno:n");
esquema("medidor", () => ({activo: false, disparar: "r2", apuntar: "l2", soloApuntando: false}),
  "activo:b disparar:B apuntar:B soloApuntando:b");
esquema("generales", () => ({cambioPerfil: true, cambioMantener: "tactil", cambioSiguiente: "derecha", cambioAnterior: "izquierda",
  decirNombre: true, avisosVoz: true, servidorMovil: true, clave: CLAVE, ajusteMando: true, ajusteMantener: "share",
  fuerzaMando: true, fuerzaMantener: "silenciar", monitor: nuevo("monitor"), medidor: nuevo("medidor")}),
  "cambioPerfil:b cambioMantener:B cambioSiguiente:B cambioAnterior:B decirNombre:b avisosVoz:b servidorMovil:b clave:s ajusteMando:b ajusteMantener:B fuerzaMando:b fuerzaMantener:B monitor:@monitor medidor:@medidor");

// ---------- Ayuda al apuntado (modelo.rs: impl AyudaApuntado) ----------
const recortar = (v, a, b) => Math.min(Math.max(v, Math.min(a, b)), Math.max(a, b));
function recortados(ay, t, h, e) {
  const l = ay.limites;
  return l.activos ? [recortar(t, l.tamanoMin, l.tamanoMax), recortar(h, l.hzMin, l.hzMax), recortar(e, l.entradaMin, l.entradaMax)] : [t, h, e];
}
const efectivos = ay => [...recortados(ay, ay.tamano, ay.hz, ay.entradaMs), ay.ceder];
function limitado(ay) { const e = efectivos(ay); return e[0] !== ay.tamano || e[1] !== ay.hz || e[2] !== ay.entradaMs; }
function normalizar(ay) { const e = efectivos(ay); ay.tamano = e[0]; ay.hz = e[1]; ay.entradaMs = e[2]; }
const varianteSel = ay => (ay.varianteActiva ? ay.variantes.find(v => v.id === ay.varianteActiva) : undefined);
function varianteModificada(ay) {
  const v = varianteSel(ay);
  if (!v) return false;
  const r = recortados(ay, v.tamano, v.hz, v.entradaMs);
  return !(v.forma === ay.forma && r[0] === ay.tamano && r[1] === ay.hz && r[2] === ay.entradaMs && v.ceder === ay.ceder);
}
function aplicarVariante(ay, v) {
  Object.assign(ay, {forma: v.forma, tamano: v.tamano, hz: v.hz, entradaMs: v.entradaMs, ceder: v.ceder});
  ay.varianteActiva = v.id;
  normalizar(ay);
}
function indicePatron(ay) {
  const i = PATRONES.findIndex(p => {
    const r = recortados(ay, p.tamano, p.hz, p.entradaMs);
    return p.forma === ay.forma && r[0] === ay.tamano && r[1] === ay.hz && r[2] === ay.entradaMs && p.ceder === ay.ceder;
  });
  return i < 0 ? null : i;
}
function aplicarPatron(ay, i) {
  const p = PATRONES[i];
  Object.assign(ay, {forma: p.forma, tamano: p.tamano, hz: p.hz, entradaMs: p.entradaMs, ceder: p.ceder});
  delete ay.varianteActiva;
  normalizar(ay);
}
function guardarVariante(ay, nombre) {
  const limpio = (nombre || "").trim(), base = indicePatron(ay);
  const v = nuevo("variante", {nombre: limpio || "Variante " + (ay.variantes.length + 1), base: base === null ? -1 : base,
    forma: ay.forma, tamano: ay.tamano, hz: ay.hz, entradaMs: ay.entradaMs, ceder: ay.ceder});
  ay.varianteActiva = v.id;
  ay.variantes.push(v);
}
function actualizarVariante(ay) {
  const v = varianteSel(ay);
  if (v) Object.assign(v, {forma: ay.forma, tamano: ay.tamano, hz: ay.hz, entradaMs: ay.entradaMs, ceder: ay.ceder});
}
function borrarVariante(ay, id) {
  ay.variantes = ay.variantes.filter(v => v.id !== id);
  if (ay.varianteActiva === id) delete ay.varianteActiva;
}
const opcionesAyuda = ay => [...PATRONES.map((_, i) => ({p: i})), ...ay.variantes.map(v => ({v: v.id}))];
function opcionActual(ay) {
  const v = varianteSel(ay);
  if (v && !varianteModificada(ay)) { const i = ay.variantes.findIndex(x => x.id === v.id); if (i >= 0) return PATRONES.length + i; }
  return indicePatron(ay);
}
function aplicarOpcion(ay, i) {
  const o = opcionesAyuda(ay)[i];
  if (!o) return "";
  if (o.p !== undefined) { aplicarPatron(ay, o.p); return PATRONES[o.p].nombre; }
  const v = ay.variantes.find(x => x.id === o.v);
  if (!v) return "";
  aplicarVariante(ay, clon(v));
  return v.nombre;
}

// ---------- Widgets y resumen de «En vivo» (modelo.rs) ----------
const widget = (tipo, objetivo) => (objetivo ? {id: nuevoId(), tipo, objetivo} : {id: nuevoId(), tipo});
function catalogoWidgets(p) {
  const c = [widget("antiRecoil"), widget("ayuda")];
  if (p.turbos.length > 1) c.push(widget("turbos"));
  c.push(...p.turbos.map(t => widget("turbo", t.id)));
  if (p.macros.length > 1) c.push(widget("macros"));
  c.push(...p.macros.map(m => widget("macro", m.id)));
  c.push(widget("pausa"));
  return c.filter(w => !p.widgets.some(x => x.tipo === w.tipo && x.objetivo === w.objetivo));
}
function widgetsBasicos(p) {
  const b = [widget("antiRecoil"), widget("ayuda")];
  if (p.macros.length) b.push(p.macros.length === 1 ? widget("macro", p.macros[0].id) : widget("macros"));
  if (p.turbos.length) b.push(p.turbos.length === 1 ? widget("turbo", p.turbos[0].id) : widget("turbos"));
  b.push(widget("pausa"));
  return b;
}
function estadoWidget(w, p, ar, ay, pausado) {
  const e = (nombre, detalle, on) => ({id: w.id, tipo: w.tipo, nombre, detalle, on});
  switch (w.tipo) {
    case "antiRecoil": return e("Anti-recoil", p.antiRecoil.progresivo ? "progresivo" : "fuerza " + redondear(p.antiRecoil.vertical), ar);
    case "ayuda": {
      const tam = efectivos(p.ayuda)[0];
      const t = redondear(tam) === tam ? String(tam) : tam.toFixed(1);
      return e("Ayuda al apuntado", (p.ayuda.forma === "circulo" ? "círculos" : "temblor") + " · " + t + " %", ay);
    }
    case "pausa": return e("Pausa", pausado ? "la consola recibe el mando quieto" : "el mando pasa a la consola", pausado);
    case "turbos": {
      const n = p.turbos.filter(t => t.activo).length;
      return e("Turbo", p.turbos.length ? n + " de " + p.turbos.length + " encendidos" : "sin turbos", n > 0);
    }
    case "turbo": {
      const t = p.turbos.find(t => t.id === w.objetivo);
      return t ? e("Turbo " + CORTO[t.boton], redondear(t.hz) + " pulsaciones/s", t.activo) : null;
    }
    case "macros": {
      const n = p.macros.filter(m => m.activa).length;
      return e("Macros", p.macros.length ? n + " de " + p.macros.length + " activas" : "sin macros", n > 0);
    }
    case "macro": {
      const m = p.macros.find(m => m.id === w.objetivo);
      if (!m) return null;
      let d = "con " + CORTO[m.disparador];
      if (m.atajo) d += " · atajo " + CORTO[m.atajoMantener] + "+" + CORTO[m.atajoPulsar];
      return e(m.nombre, d, m.activa);
    }
  }
  return null;
}
const nombreWidget = (w, p) => { const e = estadoWidget(w, p, false, false, false); return e ? e.nombre : "—"; };
function resumenFunciones(p, g, ar, ay) {
  const f = [], anadir = (nombre, detalle, on) => f.push({nombre, detalle, on});
  const lista = b => b.map(x => CORTO[x]).join(", ");
  if (p.antiRecoil.activo || ar) anadir("Anti-recoil", p.antiRecoil.progresivo ? "progresivo" : "fuerza fija", ar);
  if (p.ayuda.activo || ay) anadir("Ayuda al apuntado", (p.ayuda.forma === "circulo" ? "círculos" : "temblor") + ", con " + CORTO[p.ayuda.boton], ay);
  if (p.turbos.length) anadir("Turbo", p.turbos.map(t => CORTO[t.boton] + " " + redondear(t.hz) + "/s").join(", "), true);
  const activas = p.macros.filter(m => m.activa);
  if (p.macros.length) anadir(activas.length === 1 ? "Macro" : "Macros",
    activas.length ? activas.map(m => m.nombre + " (" + CORTO[m.disparador] + ")").join(", ") : "ninguna activa", activas.length > 0);
  const cambiados = BOTONES.filter(b => b in p.reasignar);
  if (cambiados.length) anadir("Botones cambiados", lista(cambiados), true);
  if (p.alternar.length) anadir("Alternar", lista(p.alternar), true);
  const largas = BOTONES.filter(b => b in p.pulsacionLarga);
  if (largas.length) anadir("Pulsación larga", lista(largas), true);
  if (p.intercambiarSticks) anadir("Sticks intercambiados", "", true);
  if (g.medidor.activo) anadir("Mi control", "midiendo", true);
  if (g.monitor.activo) anadir("Monitor de señal", "", true);
  return f;
}

// ---------- Combinaciones del mando (modelo.rs) ----------
const DPAD = bit("arriba") | bit("abajo") | bit("derecha") | bit("izquierda");
function comboFuerza(e, flanco, g) {
  if (!(g.fuerzaMando && pulsado(e, g.fuerzaMantener))) return [false, 0, 0];
  const paso = flanco & bit("arriba") ? 1 : flanco & bit("abajo") ? -1 : 0;
  const lateral = flanco & bit("derecha") ? 1 : flanco & bit("izquierda") ? -1 : 0;
  e.botones &= ~DPAD;
  return [true, paso, lateral];
}
const comboMacros = (e, flanco, p) => p.macros
  .filter(m => m.atajo && flanco & bit(m.atajoPulsar) && (m.atajoMantener === m.atajoPulsar || pulsado(e, m.atajoMantener)))
  .map(m => m.id);
const AJUSTES_RAPIDOS = [
  ["Anti-recoil fuerza", 0, 100, 2, p => p.antiRecoil.vertical, (p, v) => { p.antiRecoil.vertical = v; }],
  ["Anti-recoil lateral", -50, 50, 2, p => p.antiRecoil.horizontal, (p, v) => { p.antiRecoil.horizontal = v; }],
  ["Ayuda tamaño", 1, 30, 1, p => p.ayuda.tamano, (p, v) => { p.ayuda.tamano = v; }],
  ["Ayuda velocidad", 2, 40, 1, p => p.ayuda.hz, (p, v) => { p.ayuda.hz = v; }],
  ["Sensibilidad horizontal", 20, 200, 5, p => p.der.sensX, (p, v) => { p.der.sensX = v; }],
  ["Sensibilidad vertical", 20, 200, 5, p => p.der.sensY, (p, v) => { p.der.sensY = v; }],
];

// ---------- Almacén: perfiles y ajustes (modelo.rs: Almacen) ----------
const PERMITIDOS = ["cambioPerfil", "cambioMantener", "cambioSiguiente", "cambioAnterior", "decirNombre", "avisosVoz",
  "ajusteMando", "ajusteMantener", "fuerzaMando", "fuerzaMantener"];
function ponerEn(d, ruta, valor) {
  const [clave, ...resto] = ruta;
  if (clave === undefined || !d || typeof d !== "object" || Array.isArray(d)) return false;
  if (!Object.prototype.hasOwnProperty.call(d, clave)) {
    // Los opcionales vacíos no se escriben en el JSON; se pueden poner igual si son del modelo
    if (resto.length || !(clave === "varianteActiva" || clave === "objetivo")) return false;
  }
  if (!resto.length) { d[clave] = valor; return true; }
  return ponerEn(d[clave], resto, valor);
}
class Almacen {
  constructor(perfiles, activoId, generales) {
    this.perfiles = perfiles; this.activoId = activoId; this.generales = generales;
    this.ajusteIndice = 0; this.version = 1;
  }
  cambiado() { this.version++; }
  activo() { return this.perfiles.find(p => p.id === this.activoId) || this.perfiles[0]; }
  ponerActivo(p) {
    const i = this.perfiles.findIndex(x => x.id === p.id);
    if (i >= 0) { normalizar(p.ayuda); this.perfiles[i] = p; this.cambiado(); }
  }
  conActivo(f) { const p = clon(this.activo()); const r = f(p); this.ponerActivo(p); return r; }
  ponerGenerales(g) { this.generales = g; this.cambiado(); }
  seleccionar(id) { if (this.perfiles.some(p => p.id === id)) { this.activoId = id; this.cambiado(); } }
  nuevo() {
    const p = nuevo("perfil", {nombre: "Perfil " + (this.perfiles.length + 1), color: COLORES[this.perfiles.length % COLORES.length]});
    this.activoId = p.id; this.perfiles.push(p); this.cambiado();
  }
  duplicar() {
    const p = clon(this.activo());
    p.id = nuevoId(); p.nombre = this.activo().nombre + " (copia)"; p.color = COLORES[this.perfiles.length % COLORES.length];
    this.activoId = p.id; this.perfiles.push(p); this.cambiado();
  }
  borrarActivo() {
    if (this.perfiles.length < 2) return;
    const i = this.perfiles.findIndex(p => p.id === this.activoId);
    if (i < 0) return;
    this.perfiles.splice(i, 1);
    this.activoId = this.perfiles[Math.max(i - 1, 0)].id;
    this.cambiado();
  }
  cambiarPerfil(paso) {
    const i = this.perfiles.findIndex(p => p.id === this.activoId), n = this.perfiles.length;
    if (i < 0) return;
    for (let k = 1; k <= n; k++) {
      const c = this.perfiles[(((i + paso * k) % n) + n) % n];
      if (c.enCiclo && c.id !== this.activoId) { this.activoId = c.id; this.cambiado(); return; }
    }
  }
  ajusteRapido(dParam, dValor) {
    const n = AJUSTES_RAPIDOS.length;
    if (dParam) {
      this.ajusteIndice = (this.ajusteIndice + dParam + n) % n;
      const a = AJUSTES_RAPIDOS[this.ajusteIndice];
      return a[0] + " " + redondear(a[4](this.activo()));
    }
    const a = AJUSTES_RAPIDOS[this.ajusteIndice];
    const v = Math.min(Math.max(a[4](this.activo()) + dValor * a[3], a[1]), a[2]);
    this.conActivo(p => a[5](p, v));
    return String(redondear(v));
  }
  ajustarFuerza(d) {
    return this.conActivo(p => {
      const ar = p.antiRecoil;
      ar.vertical = Math.min(Math.max(ar.vertical + d * 2, 0), 100);
      if (ar.progresivo) ar.verticalFinal = Math.min(Math.max(ar.verticalFinal + d * 2, 0), 100);
      let frase = "Anti-recoil " + redondear(ar.vertical);
      if (ar.progresivo) frase += ", final " + redondear(ar.verticalFinal);
      if (!ar.activo) frase += ", apagado";
      return frase;
    });
  }
  ajustarLateral(d) {
    return this.conActivo(p => {
      const ar = p.antiRecoil;
      ar.horizontal = Math.min(Math.max(ar.horizontal + d * 2, -50), 50);
      const v = redondear(ar.horizontal);
      let frase = v > 0 ? "Lateral derecha " + v : v < 0 ? "Lateral izquierda " + -v : "Lateral 0";
      if (!ar.activo) frase += ", apagado";
      return frase;
    });
  }
  alternarMacro(id) {
    if (!this.activo().macros.some(m => m.id === id)) return null;
    return this.conActivo(p => { const m = p.macros.find(m => m.id === id); m.activa = !m.activa; return m.nombre + " " + (m.activa ? "activada" : "desactivada"); });
  }
  alternarMacros() {
    return this.conActivo(p => { const on = !p.macros.some(m => m.activa); p.macros.forEach(m => { m.activa = on; }); return on ? "Macros activadas" : "Macros desactivadas"; });
  }
  alternarTurbo(id) {
    if (!this.activo().turbos.some(t => t.id === id)) return null;
    return this.conActivo(p => { const t = p.turbos.find(t => t.id === id); t.activo = !t.activo; return "Turbo en " + CORTO[t.boton] + " " + (t.activo ? "encendido" : "apagado"); });
  }
  alternarTurbos() {
    return this.conActivo(p => { const on = !p.turbos.some(t => t.activo); p.turbos.forEach(t => { t.activo = on; }); return on ? "Turbo encendido" : "Turbo apagado"; });
  }
  anadirWidget(w) {
    if (this.activo().widgets.some(x => x.tipo === w.tipo && x.objetivo === w.objetivo)) return;
    this.conActivo(p => p.widgets.push(w));
  }
  quitarWidget(id) { this.conActivo(p => { p.widgets = p.widgets.filter(w => w.id !== id); }); }
  moverWidget(id, paso) {
    const i = this.activo().widgets.findIndex(w => w.id === id), j = i + paso;
    if (i < 0 || j < 0 || j >= this.activo().widgets.length) return;
    this.conActivo(p => { [p.widgets[i], p.widgets[j]] = [p.widgets[j], p.widgets[i]]; });
  }
  ponerRuta(ruta, valor) {
    const partes = String(ruta).split(".").filter(Boolean);
    if (!partes.length) return "ruta vacía";
    if (partes[0] === "generales") {
      const simple = partes.length === 2 && PERMITIDOS.includes(partes[1]);
      const monitor = partes.length === 3 && partes[1] === "monitor";
      const medidor = partes.length === 3 && partes[1] === "medidor";
      if (!(simple || monitor || medidor)) return "ajuste no permitido";
      if (monitor && partes[2] !== "activo" && !(typeof valor === "number" && isFinite(valor) && valor > 0)) {
        return "el umbral tiene que ser un número mayor que 0";
      }
      const d = clon(this.generales);
      if (!ponerEn(d, partes.slice(1), valor)) return "ruta desconocida: " + ruta;
      try { this.ponerGenerales(leerObj(E.generales, d)); } catch (e) { return "valor no válido para " + ruta; }
    } else {
      if (partes[0] === "id") return "ajuste no permitido";
      const d = clon(this.activo());
      if (!ponerEn(d, partes, valor)) return "ruta desconocida: " + ruta;
      // Lo que falte (un turbo o una macro nuevos del móvil) va con su valor por defecto
      let p;
      try { p = leerObj(E.perfil, d); } catch (e) { return "valor no válido para " + ruta; }
      p.id = this.activoId;
      this.ponerActivo(p);
    }
    return null;
  }
  cambiarPatronAyuda(paso) {
    return this.conActivo(p => {
      const n = opcionesAyuda(p.ayuda).length, a = opcionActual(p.ayuda);
      const actual = a === null ? (paso > 0 ? -1 : 0) : a;
      return aplicarOpcion(p.ayuda, (((actual + paso) % n) + n) % n);
    });
  }
  usarPatronAyuda(i) { if (i >= 0 && i < PATRONES.length) this.conActivo(p => aplicarPatron(p.ayuda, i)); }
  usarVarianteAyuda(id) {
    const v = this.activo().ayuda.variantes.find(v => v.id === id);
    if (v) this.conActivo(p => aplicarVariante(p.ayuda, clon(v)));
  }
  crearPerfilesPorSituacion() {
    const base = this.activo();
    let anadidos = 0;
    const crear = (nombre, color, ajustar) => {
      if (this.perfiles.some(p => p.nombre === nombre)) return;
      const p = clon(base);
      p.id = nuevoId(); p.nombre = nombre; p.color = color; p.enCiclo = true;
      ajustar(p);
      this.perfiles.push(p);
      anadidos++;
    };
    crear("Corto alcance", "#FF6A00", p => {
      Object.assign(p.der, {sensX: 120, sensY: 120, curva: 1, suavizado: 0});
      Object.assign(p.antiRecoil, {vertical: 15, progresivo: false});
      aplicarPatron(p.ayuda, 2);
    });
    crear("Largo alcance", "#00B0FF", p => {
      Object.assign(p.der, {sensX: 80, sensY: 80, curva: 1.6, suavizado: 15});
      Object.assign(p.antiRecoil, {vertical: 30, progresivo: true, verticalFinal: 15, transicionMs: 1200});
      aplicarPatron(p.ayuda, 0);
    });
    if (anadidos) this.cambiado();
    return anadidos;
  }
}

// ---------- Procesador (procesador.rs, línea a línea) ----------
const eje = v => (v - 127.5) / 127.5;
const aByte = v => Math.round(smin(smax(127.5 + v * 127.5, 0), 255));
const reposo = () => ({botones: 0, lx: 128, ly: 128, rx: 128, ry: 128, l2: 0, r2: 0});
const destino = (p, b) => (!(b in p.reasignar) ? (b !== "silenciar" ? b : null) : (BOTONES.includes(p.reasignar[b]) ? p.reasignar[b] : null));
const diagVacio = () => ({encendida: false, aplicando: false, forma: "circulo", tamano: 0, hz: 0, entradaMs: 0, ceder: 0,
  limitada: false, rampa: 0, cesion: 1, amplitud: 0, fase: 0, offX: 0, offY: 0, enTransicion: false});
function curva(v, a) {
  const dz = a.zonaMuerta / 100, ext = smax(a.zonaExterna / 100, dz + 0.01);
  if (!(v > dz)) return 0;
  const n = Math.pow(smin((v - dz) / (ext - dz), 1), smax(a.curva, 0.1));
  const anti = a.antiZonaMuerta / 100;
  return anti + (1 - anti) * n;
}
function forma(x, y, a) {
  let sx, sy;
  if (a.formaCruz) {
    sx = (x < 0 ? -1 : 1) * curva(smin(Math.abs(x), 1), a);
    sy = (y < 0 ? -1 : 1) * curva(smin(Math.abs(y), 1), a);
  } else {
    const m = smin(Math.hypot(x, y), 1);
    if (!(m > 0)) return [0, 0];
    const s = curva(m, a);
    sx = x / Math.hypot(x, y) * s;
    sy = y / Math.hypot(x, y) * s;
  }
  sx *= a.sensX / 100;
  sy *= a.sensY / 100;
  if (a.invertirX) sx = -sx;
  if (a.invertirY) sy = -sy;
  return [sx, sy];
}
function stick(x, y, a, s, t, dt) {
  let [ox, oy] = forma(x, y, a);
  if (a.aceleracion > 0 && Math.hypot(x, y) > 0.85) {
    const desde = s.tope === null ? t : s.tope;
    s.tope = desde;
    const k = a.tiempoAceleracion > 0 ? smin((t - desde) * 1000 / a.tiempoAceleracion, 1) : 1;
    const f = 1 + a.aceleracion / 100 * k;
    ox *= f; oy *= f;
  } else s.tope = null;
  const lim = a.limite / 100, m = Math.hypot(ox, oy);
  if (m > lim && m > 0) { ox *= lim / m; oy *= lim / m; }
  if (a.suavizado > 0) {
    const tau = a.suavizado / 100 * 0.15, alfa = dt / (tau + dt);
    s.x += (ox - s.x) * alfa; s.y += (oy - s.y) * alfa;
    ox = s.x; oy = s.y;
  } else { s.x = ox; s.y = oy; }
  return [smin(smax(ox, -1), 1), smin(smax(oy, -1), 1)];
}
function gatillo(v, a) {
  const x = v / 255, dz = a.zonaMuerta / 100;
  if (!(x > dz && x > 0.01)) return 0;
  if (a.disparoRapido) return 1;
  const ext = smax(a.zonaExterna / 100, dz + 0.01);
  return Math.pow(smin((x - dz) / (ext - dz), 1), smax(a.curva, 0.1));
}
const vector = (f, r, fase) => (f === "circulo" ? [r * Math.cos(2 * Math.PI * fase), r * Math.sin(2 * Math.PI * fase)] : [r * Math.sin(2 * Math.PI * fase), 0]);
const ENLACE = 0.15;

class Procesador {
  constructor() {
    this.ar = false; this.ay = false; this.diag = diagVacio();
    this.ayudaEnAjustes = null; this.ayudaDesde = null; this.efAnterior = null; this.faseDesfase = 0; this.rUltimo = 0;
    this.correccionR = 0; this.correccionDesde = 0; this.formaAnterior = null; this.formaCambioDesde = 0;
    this.perfilId = null; this.activoEnAjustes = null; this.entradaAntes = 0; this.tAntes = null;
    this.turboDesde = new Map(); this.macroDesde = new Map(); this.disparandoDesde = null; this.alternados = 0;
    this.pulsadoDesde = new Map(); this.toqueHasta = new Map();
    this.izq = {x: 0, y: 0, tope: null}; this.der = {x: 0, y: 0, tope: null};
  }
  procesar(e, p, t) {
    if (this.perfilId !== p.id) {
      this.perfilId = p.id;
      this.turboDesde.clear(); this.macroDesde.clear(); this.alternados = 0; this.pulsadoDesde.clear(); this.toqueHasta.clear();
      this.efAnterior = null; this.faseDesfase = 0; this.correccionR = 0; this.formaAnterior = null;
      this.activoEnAjustes = null; this.ayudaEnAjustes = null;
    }
    if (p.ayuda.activo !== this.ayudaEnAjustes) { this.ayudaEnAjustes = p.ayuda.activo; this.ay = p.ayuda.activo; }
    if (p.antiRecoil.activo !== this.activoEnAjustes) { this.activoEnAjustes = p.antiRecoil.activo; this.ar = p.antiRecoil.activo; }
    const dt = smin(smax(t - (this.tAntes === null ? t : this.tAntes), 0), 0.05);
    this.tAntes = t;
    const flanco = e.botones & ~this.entradaAntes, soltados = this.entradaAntes & ~e.botones;
    this.entradaAntes = e.botones;

    // 1. Sticks
    let ix = eje(e.lx), iy = -eje(e.ly), dx = eje(e.rx), dy = -eje(e.ry);
    if (p.intercambiarSticks) { [ix, dx] = [dx, ix]; [iy, dy] = [dy, iy]; }
    [ix, iy] = stick(ix, iy, p.izq, this.izq, t, dt);
    [dx, dy] = stick(dx, dy, p.der, this.der, t, dt);

    // 2. Gatillos
    let l2 = gatillo(e.l2, p.l2), r2 = gatillo(e.r2, p.r2);
    const L2 = bit("l2"), R2 = bit("r2");
    let entrada = e.botones & ~(L2 | R2);
    if (l2 > 0) entrada |= L2;
    if (r2 > 0) entrada |= R2;

    // 3. Alternar
    for (const b of p.alternar) {
      const k = bit(b);
      if (flanco & k) this.alternados ^= k;
      if (this.alternados & k) entrada |= k; else entrada &= ~k;
      if (b === "l2") l2 = this.alternados & k ? 1 : 0;
      if (b === "r2") r2 = this.alternados & k ? 1 : 0;
    }

    // 4. Pulsación larga
    let porLarga = 0;
    for (const origen of Object.keys(p.pulsacionLarga).sort()) {
      if (!BOTONES.includes(origen)) continue;
      const b = origen, k = bit(b), d = p.pulsacionLarga[origen], larga = BOTONES.includes(d) ? d : null;
      if (e.botones & k) {
        const desde = this.pulsadoDesde.has(b) ? this.pulsadoDesde.get(b) : t;
        this.pulsadoDesde.set(b, desde);
        if ((t - desde) * 1000 >= p.msLarga && larga) porLarga |= bit(larga);
      } else if (soltados & k) {
        if (this.pulsadoDesde.has(b)) {
          if ((t - this.pulsadoDesde.get(b)) * 1000 < p.msLarga) this.toqueHasta.set(b, t + 0.08);
          this.pulsadoDesde.delete(b);
        }
      }
      const hasta = this.toqueHasta.get(b);
      if (hasta !== undefined && t < hasta) {
        entrada |= k;
        if (b === "l2") l2 = 1;
        if (b === "r2") r2 = 1;
      } else {
        this.toqueHasta.delete(b);
        entrada &= ~k;
        if (b === "l2") l2 = 0;
        if (b === "r2") r2 = 0;
      }
    }

    // 5. Reasignación
    let salida = 0, l2s = 0, r2s = 0;
    for (const b of BOTONES) {
      if (!(entrada & bit(b))) continue;
      const d = destino(p, b);
      if (!d) continue;
      salida |= bit(d);
      const valor = b === "l2" ? l2 : b === "r2" ? r2 : 1;
      if (d === "l2") l2s = smax(l2s, valor);
      if (d === "r2") r2s = smax(r2s, valor);
    }
    salida |= porLarga;
    if (porLarga & L2) l2s = 1;
    if (porLarga & R2) r2s = 1;

    // 6. Macros
    let deMacros = 0;
    for (const m of p.macros.filter(m => m.activa && m.pasos.length)) {
      const pul = (e.botones & bit(m.disparador)) !== 0;
      if (flanco & bit(m.disparador) && !this.macroDesde.has(m.id)) this.macroDesde.set(m.id, t);
      if (!this.macroDesde.has(m.id)) continue;
      const desde = this.macroDesde.get(m.id);
      const total = m.pasos.reduce((a, x) => a + Math.max(x.ms, 1), 0) / 1000;
      let pasado = t - desde;
      if (pasado >= total) {
        if (m.repetir && pul) pasado %= total;
        else { this.macroDesde.delete(m.id); continue; }
      }
      let acumulado = 0;
      for (const paso of m.pasos) {
        acumulado += Math.max(paso.ms, 1) / 1000;
        if (pasado < acumulado) { for (const b of paso.botones) deMacros |= bit(b); break; }
      }
    }
    for (const m of p.macros.filter(m => m.activa && m.bloquearDisparador && e.botones & bit(m.disparador))) {
      const d = destino(p, m.disparador);
      if (!d || deMacros & bit(d)) continue;
      salida &= ~bit(d);
      if (d === "l2") l2s = 0;
      if (d === "r2") r2s = 0;
    }
    salida |= deMacros;
    if (deMacros & L2) l2s = 1;
    if (deMacros & R2) r2s = 1;

    // 7. Turbo
    for (const tb of p.turbos.filter(tb => tb.hz > 0 && tb.activo)) {
      if (!(salida & bit(tb.boton))) { this.turboDesde.delete(tb.boton); continue; }
      const desde = this.turboDesde.has(tb.boton) ? this.turboDesde.get(tb.boton) : t;
      this.turboDesde.set(tb.boton, desde);
      if (((t - desde) * tb.hz) % 1 >= tb.ciclo / 100) {
        salida &= ~bit(tb.boton);
        if (tb.boton === "l2") l2s = 0;
        if (tb.boton === "r2") r2s = 0;
      }
    }

    // 8. Anti-recoil
    const ar = p.antiRecoil;
    const combinacion = ar.atajoMantener === ar.atajoPulsar ? (flanco & bit(ar.atajoPulsar)) !== 0
      : pulsado(e, ar.atajoMantener) && (flanco & bit(ar.atajoPulsar)) !== 0;
    if (ar.atajo && combinacion) this.ar = !this.ar;
    const enSalida = b => (b === "l2" ? l2s > 0.1 : b === "r2" ? r2s > 0.1 : (salida & bit(b)) !== 0);
    const disparando = enSalida(ar.disparar) && (!ar.soloApuntando || enSalida(ar.apuntar));
    if (this.ar && disparando) {
      const desde = this.disparandoDesde === null ? t : this.disparandoDesde;
      this.disparandoDesde = desde;
      const pasadoMs = (t - desde) * 1000 - ar.retardoMs;
      if (pasadoMs >= 0) {
        let fuerza = ar.vertical;
        if (ar.progresivo) {
          const k = ar.transicionMs > 0 ? smin(pasadoMs / ar.transicionMs, 1) : 1;
          fuerza = ar.vertical + (ar.verticalFinal - ar.vertical) * k;
        }
        dy -= fuerza / 100;
        dx += ar.horizontal / 100;
      }
    } else this.disparandoDesde = null;

    // 9. Ayuda al apuntado
    const ay = p.ayuda;
    const comboAyuda = ay.atajoMantener === ay.atajoPulsar ? (flanco & bit(ay.atajoPulsar)) !== 0
      : pulsado(e, ay.atajoMantener) && (flanco & bit(ay.atajoPulsar)) !== 0;
    if (ay.atajo && comboAyuda) this.ay = !this.ay;
    const [efT, efH, efE, efC] = efectivos(ay);
    const diag = Object.assign(diagVacio(), {encendida: this.ay, forma: ay.forma, tamano: efT, hz: efH, entradaMs: efE, ceder: efC, limitada: limitado(ay)});
    if (this.ay && enSalida(ay.boton) && (!ay.tambienDisparando || enSalida(ar.disparar))) {
      const desde = this.ayudaDesde === null ? t : this.ayudaDesde;
      this.ayudaDesde = desde;
      let manual = false;
      const a = this.efAnterior;
      if (a && (a.tamano !== efT || a.hz !== efH || a.entradaMs !== efE || a.ceder !== efC || a.forma !== ay.forma)) {
        manual = true;
        if (a.hz !== efH) this.faseDesfase = (t - desde) * a.hz + this.faseDesfase - (t - desde) * efH;
        if (a.forma !== ay.forma) { this.formaAnterior = a.forma; this.formaCambioDesde = t; }
      }
      this.efAnterior = {tamano: efT, hz: efH, entradaMs: efE, ceder: efC, forma: ay.forma};
      const fase = ((t - desde) * efH + this.faseDesfase) % 1;
      const suave = efE > 0 ? smin((t - desde) * 1000 / efE, 1) : 1;
      const tuyo = smin(Math.hypot(dx, dy), 1);
      const r0 = efT / 100 * suave * (1 - efC / 100 * tuyo);
      if (manual) { this.correccionR = this.rUltimo - r0; this.correccionDesde = t; }
      let correccion = 0;
      if (this.correccionR !== 0) {
        const k = 1 - (t - this.correccionDesde) / ENLACE;
        if (k > 0) correccion = this.correccionR * k; else this.correccionR = 0;
      }
      const r = r0 + correccion;
      this.rUltimo = r;
      let [vx, vy] = vector(ay.forma, r, fase);
      if (this.formaAnterior !== null) {
        const k = (t - this.formaCambioDesde) / ENLACE;
        if (k < 1) { const [ox, oy] = vector(this.formaAnterior, r, fase); vx = ox + (vx - ox) * k; vy = oy + (vy - oy) * k; }
        else this.formaAnterior = null;
      }
      dx += vx; dy += vy;
      Object.assign(diag, {aplicando: true, rampa: suave, cesion: 1 - efC / 100 * tuyo, amplitud: r, fase: fase - Math.floor(fase),
        offX: vx, offY: vy, enTransicion: correccion !== 0 || this.formaAnterior !== null});
    } else {
      this.ayudaDesde = null; this.efAnterior = null; this.faseDesfase = 0; this.correccionR = 0; this.formaAnterior = null; this.rUltimo = 0;
    }
    this.diag = diag;

    return {botones: salida, lx: aByte(ix), ly: aByte(-iy), rx: aByte(dx), ry: aByte(-dy),
      l2: Math.round(smin(smax(l2s, 0), 1) * 255), r2: Math.round(smin(smax(r2s, 0), 1) * 255)};
  }
}

// ---------- Monitor de la señal (monitor.rs) ----------
function analizarMonitor(x, y, dt, l) {
  const NOMBRE = ["Correcta", "Advertencia", "Anomalía"];
  const inf = {estado: 0, metricas: {muestras: 0, maxAbs: 0, maxSalto: 0, maxVelocidad: 0, maxAceleracion: 0, cambiosSigno: 0, noNumericos: 0}, eventos: [], omitidos: 0};
  const n = Math.min(x.length, y.length);
  inf.metricas.muestras = n;
  if (!n) return {inf, NOMBRE};
  const anotar = (i, eje, g, v, lim, motivo) => {
    if (g > inf.estado) inf.estado = g;
    if (inf.eventos.length < 50) inf.eventos.push({i, eje, g, v, lim, motivo}); else inf.omitidos++;
  };
  let cambios = 0, pendientes = 0;
  for (const [nombre, s] of [["x", x], ["y", y]]) {
    let ant = null, velAnt = null, signoAnt = 0;
    for (let i = 0; i < n; i++) {
      const v = s[i];
      if (!isFinite(v)) { inf.metricas.noNumericos++; anotar(i, nombre, 2, v, l.maxAbs, "valor no numérico"); ant = null; velAnt = null; continue; }
      inf.metricas.maxAbs = smax(inf.metricas.maxAbs, Math.abs(v));
      if (Math.abs(v) > l.maxAbs) anotar(i, nombre, 2, v, l.maxAbs, "fuera del rango del stick");
      if (ant !== null) {
        const salto = Math.abs(v - ant);
        inf.metricas.maxSalto = smax(inf.metricas.maxSalto, salto);
        if (salto > l.maxSalto) anotar(i, nombre, 2, salto, l.maxSalto, "salto entre dos muestras seguidas");
        const vel = (v - ant) / dt;
        inf.metricas.maxVelocidad = smax(inf.metricas.maxVelocidad, Math.abs(vel));
        if (Math.abs(vel) > l.maxVelocidad) anotar(i, nombre, 1, Math.abs(vel), l.maxVelocidad, "velocidad por encima de la configurada");
        if (velAnt !== null) {
          const acel = Math.abs(vel - velAnt) / dt;
          inf.metricas.maxAceleracion = smax(inf.metricas.maxAceleracion, acel);
          if (acel > l.maxAceleracion) anotar(i, nombre, 1, acel, l.maxAceleracion, "aceleración por encima de la configurada");
        }
        const signo = Math.abs(v - ant) < 1e-4 ? 0 : v > ant ? 1 : -1;
        if (signo) { pendientes++; if (signoAnt && signo !== signoAnt) cambios++; signoAnt = signo; }
        velAnt = vel;
      }
      ant = v;
    }
  }
  if (pendientes > 10) {
    const f = cambios / pendientes;
    inf.metricas.cambiosSigno = f;
    if (f > l.maxCambiosSigno) {
      if (inf.estado < 1) inf.estado = 1;
      inf.eventos.push({i: n - 1, eje: "x+y", g: 1, v: f, lim: l.maxCambiosSigno, motivo: "cambia de sentido casi en cada muestra"});
    }
  }
  return {inf, NOMBRE};
}

// ---------- Mi control (medidor.rs) ----------
const DESDE_2001 = 978307200;
const ahora2001 = () => Date.now() / 1000 - DESDE_2001;
function analizarRafaga(x, abajo, perfil, fecha) {
  const r = {bajadaMedia: 0, constancia: 0, duracionMs: 0, fecha, id: nuevoId(), lateralMax: 0, lateralMedio: 0, muestras: 0, perfil, reaccionMs: null, temblor: 0, tirones: 0};
  const n = Math.min(x.length, abajo.length);
  r.muestras = n; r.duracionMs = n * 10;
  if (!n) return r;
  let inicio = -1;
  for (let i = 0; i < n; i++) if (abajo[i] > 0.1) { inicio = i; break; }
  r.reaccionMs = inicio < 0 ? null : inicio * 10;
  const desde = inicio < 0 ? 0 : inicio;
  let suma = 0, suma2 = 0, lat = 0;
  for (let i = desde; i < n; i++) { suma += abajo[i]; suma2 += abajo[i] * abajo[i]; lat += x[i]; }
  const m = n - desde, media = suma / m;
  r.bajadaMedia = media * 100;
  r.constancia = Math.sqrt(Math.max(suma2 / m - media * media, 0)) * 100;
  r.lateralMedio = lat / m * 100;
  r.lateralMax = Math.max(...x.slice(0, n).map(Math.abs)) * 100;
  let temblor = 0, cuenta = 0;
  for (let i = 1; i < Math.max(n, 1); i++) {
    if (Math.max(Math.abs(x[i] - x[i - 1]), Math.abs(abajo[i] - abajo[i - 1])) > 0.15) r.tirones++;
    if (i >= 2) { temblor += Math.abs(x[i] - 2 * x[i - 1] + x[i - 2]) + Math.abs(abajo[i] - 2 * abajo[i - 1] + abajo[i - 2]); cuenta++; }
  }
  r.temblor = cuenta ? temblor / cuenta * 100 : 0;
  return r;
}
function mediaRafagas(rs) {
  const m = {rafagas: rs.length, reaccion: null, sinCorregir: 0, bajada: 0, constancia: 0, lateral: 0, temblor: 0, tirones: 0};
  if (!rs.length) return m;
  const n = rs.length, con = rs.filter(r => r.reaccionMs !== null).map(r => r.reaccionMs), sum = f => rs.reduce((a, r) => a + f(r), 0);
  m.reaccion = con.length ? con.reduce((a, b) => a + b, 0) / con.length : null;
  m.sinCorregir = (n - con.length) / n;
  m.bajada = sum(r => r.bajadaMedia) / n; m.constancia = sum(r => r.constancia) / n; m.lateral = sum(r => r.lateralMedio) / n;
  m.temblor = sum(r => r.temblor) / n; m.tirones = sum(r => r.tirones) / n;
  return m;
}
function observaciones(rs) {
  if (!rs.length) return [];
  const m = mediaRafagas(rs), o = [];
  if (m.reaccion !== null && m.reaccion > 200) o.push("Tardas de media " + Math.trunc(m.reaccion) + " ms en empezar a bajar el stick.");
  if (m.sinCorregir > 0.3) o.push("En " + Math.trunc(m.sinCorregir * 100) + " % de las ráfagas no llegaste a bajar el stick.");
  if (Math.abs(m.lateral) > 3) o.push("Tiendes a irte hacia la " + (m.lateral > 0 ? "derecha" : "izquierda") + " (" + Math.abs(m.lateral).toFixed(1) + " % de media).");
  if (m.constancia > 8) o.push("Tu bajada varía bastante dentro de cada ráfaga (" + m.constancia.toFixed(1) + " %).");
  if (m.tirones > 1) o.push("Haces correcciones a tirones (" + m.tirones.toFixed(1) + " por ráfaga).");
  if (!o.length) o.push("Sin nada llamativo en estas ráfagas.");
  return o;
}
const pulsadoMedidor = (e, b) => (b === "l2" ? e.l2 > 25 : b === "r2" ? e.r2 > 25 : pulsado(e, b));
class Grabador {
  constructor() { this.x = []; this.abajo = []; this.en = false; this.inicio = 0; this.muestreado = 0; }
  tick(e, t, c, perfil) {
    const p = pulsadoMedidor(e, c.disparar) && (!c.soloApuntando || pulsadoMedidor(e, c.apuntar));
    if (p) {
      if (!this.en) { this.en = true; this.x = []; this.abajo = []; this.inicio = t; this.muestreado = t - 1; }
      if (t - this.muestreado >= 0.01 - 1e-9 && this.x.length < 3000) {
        this.muestreado = t;
        this.x.push(Math.fround((e.rx - 127.5) / 127.5));
        this.abajo.push(Math.fround((e.ry - 127.5) / 127.5));
      }
    } else if (this.en) {
      this.en = false;
      if (t - this.inicio >= 0.15 && this.x.length >= 10) return [this.x, this.abajo, perfil];
    }
    return null;
  }
  cortar() { this.en = false; this.x = []; this.abajo = []; }
}
class Medidor {
  constructor() { this.rafagas = []; this.ultimaX = []; this.ultimaAbajo = []; }
  anadir(r, x, abajo) {
    this.rafagas.push(r);
    if (this.rafagas.length > 1000) this.rafagas.splice(0, this.rafagas.length - 1000);
    if (x.length) { this.ultimaX = x; this.ultimaAbajo = abajo; }
  }
  borrar() { this.rafagas = []; this.ultimaX = []; this.ultimaAbajo = []; }
  json() {
    const r1 = v => redondear(v * 10) / 10;
    const mj = m => ({rafagas: m.rafagas, reaccion: m.reaccion === null ? null : r1(m.reaccion), sinCorregir: r1(m.sinCorregir * 100),
      bajada: r1(m.bajada), constancia: r1(m.constancia), lateral: r1(m.lateral), temblor: r1(m.temblor), tirones: r1(m.tirones)});
    const ultimas = this.rafagas.slice(-20);
    const grupos = [];
    for (const r of this.rafagas) {
      const f = new Date((r.fecha + DESDE_2001) * 1000), dia = new Date(f.getFullYear(), f.getMonth(), f.getDate()).getTime();
      const g = grupos.find(x => x[0] === dia);
      if (g) g[1].push(r); else grupos.push([dia, [r]]);
    }
    grupos.sort((a, b) => b[0] - a[0]);
    const mil = v => v.map(x => redondear(x * 1000));
    return {
      total: this.rafagas.length,
      rafagas: ultimas.slice().reverse().map(r => ({fecha: Math.trunc((r.fecha + DESDE_2001) * 1000), perfil: r.perfil,
        duracion: Math.trunc(r.duracionMs), reaccion: r.reaccionMs === null ? null : r1(r.reaccionMs), bajada: r1(r.bajadaMedia),
        constancia: r1(r.constancia), lateral: r1(r.lateralMedio), lateralMax: r1(r.lateralMax), temblor: r1(r.temblor), tirones: r.tirones})),
      media: mj(mediaRafagas(ultimas)),
      observaciones: observaciones(ultimas),
      dias: grupos.slice(0, 14).map(([d, rs]) => ({dia: d, media: mj(mediaRafagas(rs))})),
      ultima: {x: mil(this.ultimaX), abajo: mil(this.ultimaAbajo)},
    };
  }
}

// ---------- El DualSense simulado: alguien jugando ----------
// Ciclos de unos 7 s: moverse y mirar, apuntar (L2), dos ráfagas (R2) bajando un poco el stick derecho, recargar,
// saltar... Sin pulsar nunca la cruceta mientras se mantiene L1, L2, Create, Mic o el panel táctil (son las
// combinaciones del mando: cambiarían el perfil o los ajustes).
const CICLO = 7.2;
const azar = (n, k) => { const x = Math.sin(n * 127.1 + k * 311.7) * 43758.5453; return x - Math.floor(x); };
const suave = x => (x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x));
const tramo = (x, a, b, s) => suave(Math.min((x - a) / s, (b - x) / s));
const sen = (f, t, fase) => Math.sin(2 * Math.PI * f * t + (fase || 0));
const aEje = v => Math.max(0, Math.min(255, Math.round(v)));
function entradaSimulada(t) {
  const n = Math.floor(t / CICLO), x = t - n * CICLO;
  const apIni = 0.6 + 0.3 * azar(n, 1), apFin = apIni + 3.3 + 1.1 * azar(n, 2);
  const r1i = apIni + 0.45 + 0.3 * azar(n, 3), r1f = r1i + 0.7 + 0.6 * azar(n, 4);
  const r2i = r1f + 0.35 + 0.3 * azar(n, 5), r2f = Math.min(r2i + 0.5 + 0.5 * azar(n, 6), apFin - 0.15);
  const l2 = tramo(x, apIni, apFin, 0.12);
  const d1 = tramo(x, r1i, r1f, 0.04), d2 = r2f > r2i + 0.2 ? tramo(x, r2i, r2f, 0.04) : 0;
  const r2 = Math.max(d1, d2), enRafaga = d1 > 0 ? x - r1i : d2 > 0 ? x - r2i : 0;

  // Stick izquierdo: casi siempre hacia delante, con giros; al apuntar se mueve menos
  const mov = 1 - 0.65 * l2, delante = 0.55 + 0.3 * sen(0.047, t) + 0.12 * sen(0.6, t, 1);
  const lx = 128 + mov * (86 * sen(0.083, t) * Math.cos(2 * Math.PI * 0.031 * t + 1) + 14 * sen(0.71, t, 2));
  const ly = 128 - mov * (delante * 112 + 10 * sen(0.37, t, 0.5));
  // Stick derecho: mirar alrededor; al apuntar, pequeñas correcciones; al disparar, bajarlo un poco
  const mira = 1 - 0.8 * l2;
  const tirar = r2 * Math.min(1, Math.max(0, (enRafaga - 0.06 - 0.12 * azar(n, 10)) / 0.15)) * (13 + 8 * azar(n, 7));
  const rx = 128 + mira * (60 * sen(0.19, t, 0.3) + 22 * sen(0.53, t, n)) + (1 - mira) * (13 * sen(0.9, t) + 5 * sen(2.3, t))
    + r2 * (azar(n, 8) - 0.5) * 12;
  const ry = 128 + mira * (24 * sen(0.13, t, 2) + 9 * sen(0.41, t)) + (1 - mira) * 6 * sen(0.7, t) + tirar + r2 * 2.5 * sen(7, t);

  let b = 0;
  const toque = (x0, d) => x >= x0 && x < x0 + d;
  if (l2 > 0) b |= bit("l2");
  if (r2 > 0) b |= bit("r2");
  if (n % 3 === 1 && toque(0.25, 0.1)) b |= bit("triangulo");          // cambiar de arma
  if (n % 2 === 0 && toque(apFin + 0.6, 0.12)) b |= bit("x");          // saltar
  if (toque(apFin + 1.0 + 0.2 * azar(n, 9), 0.16)) b |= bit("cuadrado"); // recargar
  if (n % 2 === 1 && l2 === 0 && toque(apFin + 1.6, 0.1)) b |= bit("l3"); // correr
  if (n % 5 === 3 && toque(CICLO - 0.5, 0.1)) b |= bit("r1");           // cuerpo a cuerpo
  if (n % 4 === 2 && toque(CICLO - 0.9, 0.12)) b |= bit("arriba");      // cruceta, sin nada más pulsado
  return {botones: b, lx: aEje(lx), ly: aEje(ly), rx: aEje(rx), ry: aEje(ry), l2: aEje(l2 * 255), r2: aEje(r2 * 255)};
}

// ---------- El motor de la placa (components/motor/src/nucleo.rs) ----------
class Nucleo {
  constructor(almacen, medidor) {
    this.almacen = almacen; this.medidor = medidor; this.pausado = false; this.pedidos = []; this.aviso = null; this.rafagas = [];
    this.proc = new Procesador(); this.version = -1; this.perfil = null; this.generales = null; this.botonesAntes = 0;
    this.hist = [[], [], []]; this.grabador = new Grabador();
    this.muestreadoEn = 0; this.pintadoEn = 0; this.contadoEn = 0; this.anterior = 0; this.peor = 0; this.vueltas = 0;
    this.vueltasSeg = 1000; this.peorSeg = 1.2;
    // Lo que el firmware sabe del mando real (main/usb_ps4.c, una vez por segundo): DualSense por cable al MAX3421E
    this.mando = {hz: 490, huecoMs: 3.4, bateria: 78, estado: "cargando", envios: 1000};
    this.mandoEn = 0;
    this.directo = {entrada: reposo(), salida: reposo(), ar: false, ay: false, diag: diagVacio(), hx: [], hy: [], ha: []};
    this.revCache = [-1, false, ""];
  }
  rev() {
    const a = this.almacen;
    if (this.revCache[0] !== a.version || this.revCache[1] !== this.pausado) {
      // Cambia con cualquier ajuste, como Almacen::revision (un resumen del JSON de todo)
      const s = JSON.stringify([a.perfiles, a.activoId, a.generales]);
      let h = 0x811c9dc5;
      for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
      this.revCache = [a.version, this.pausado, String(h) + String(a.version * 7919 % 100000) + (this.pausado ? "p" : "")];
    }
    return this.revCache[2];
  }
  anunciar(texto) { this.aviso = {id: (this.aviso ? this.aviso.id : 0) + 1, texto}; }

  vuelta(entrada, t) {
    this.vueltas++;
    if (this.anterior > 0) this.peor = Math.max(this.peor, t - this.anterior);
    this.anterior = t;
    const a = this.almacen;
    if (a.version !== this.version) { this.version = a.version; this.perfil = clon(a.activo()); this.generales = clon(a.generales); }
    for (const p of this.pedidos.splice(0)) { if (p === "ar") this.proc.ar = !this.proc.ar; else this.proc.ay = !this.proc.ay; }
    const e = entrada ? Object.assign({}, entrada) : reposo(), g = this.generales, perfil = this.perfil;

    const flanco = e.botones & ~this.botonesAntes;
    this.botonesAntes = e.botones;
    const [fuerza, pasoFuerza, pasoLateral] = comboFuerza(e, flanco, g);
    if (pasoFuerza) this.anunciar(a.ajustarFuerza(pasoFuerza));
    if (pasoLateral) this.anunciar(a.ajustarLateral(pasoLateral));
    if (g.ajusteMando && !(fuerza && g.ajusteMantener === g.fuerzaMantener) && pulsado(e, g.ajusteMantener)) {
      const dv = flanco & bit("arriba") ? 1 : flanco & bit("abajo") ? -1 : 0, dp = flanco & bit("derecha") ? 1 : flanco & bit("izquierda") ? -1 : 0;
      if (dv || dp) this.anunciar(a.ajusteRapido(dp, dv));
    }
    const ay = perfil.ayuda;
    if (ay.cambioActivo && pulsado(e, ay.cambioMantener)) {
      const paso = flanco & bit(ay.cambioSiguiente) ? 1 : flanco & bit(ay.cambioAnterior) ? -1 : 0;
      if (paso) this.anunciar(a.cambiarPatronAyuda(paso));
    }
    if (flanco) for (const id of comboMacros(e, flanco, perfil)) { const f = a.alternarMacro(id); if (f) this.anunciar(f); }
    if (g.cambioPerfil && pulsado(e, g.cambioMantener)) {
      const paso = flanco & bit(g.cambioSiguiente) ? 1 : flanco & bit(g.cambioAnterior) ? -1 : 0;
      if (paso && a.perfiles.length > 1) { a.cambiarPerfil(paso); if (a.generales.decirNombre) this.anunciar(a.activo().nombre); }
    }
    if (g.medidor.activo && entrada) { const r = this.grabador.tick(e, t, g.medidor, perfil.nombre); if (r) this.rafagas.push(r); }
    else this.grabador.cortar();
    const s = this.pausado || !entrada ? reposo() : this.proc.procesar(e, perfil, t);

    if (t - this.muestreadoEn >= 0.01) {
      this.muestreadoEn = t;
      const d = this.proc.diag;
      [d.offX, d.offY, d.amplitud].forEach((v, i) => { const c = this.hist[i]; c.push(Math.fround(v)); if (c.length > 400) c.shift(); });
    }
    if (t - this.contadoEn >= 1) {
      this.vueltasSeg = this.vueltas; this.vueltas = 0;
      this.peorSeg = this.peor * 1000 + 0.15 + Math.random() * 0.5;   // el bucle real no es tan exacto como este
      this.peor = 0; this.contadoEn = t;
    }
    if (t - this.mandoEn >= 1) {
      this.mandoEn = t;
      const m = this.mando;
      m.hz = 486 + Math.floor(Math.random() * 9);
      m.huecoMs = 3.1 + Math.random() * (Math.random() < 0.2 ? 1.6 : 0.6);
      m.envios = 1000 - (Math.random() < 0.3 ? 1 : 0);
      if (Math.random() < 0.006 && m.bateria < 100) m.bateria++;   // por cable: cargando poco a poco
      m.estado = m.bateria >= 100 ? "llena" : "cargando";
    }
    if (t - this.pintadoEn >= 1 / 30) {
      this.pintadoEn = t;
      this.directo = {entrada: e, salida: s, ar: this.proc.ar, ay: this.proc.ay, diag: this.proc.diag,
        hx: this.hist[0].slice(), hy: this.hist[1].slice(), ha: this.hist[2].slice()};
    }
    return s;
  }
  lento() {
    for (const [x, abajo, nombre] of this.rafagas.splice(0)) this.medidor.anadir(analizarRafaga(x, abajo, nombre, ahora2001()), x, abajo);
  }

  instantanea() {
    const d = this.directo, a = this.almacen, p = a.activo(), m = this.mando;
    const estado = e => ({b: e.botones, lx: e.lx, ly: e.ly, rx: e.rx, ry: e.ry, l2: e.l2, r2: e.r2});
    const ultimas = v => v.slice(-150).map(x => redondear(x * 1000));
    const g = d.diag;
    const monitor = {activo: a.generales.monitor.activo};
    if (monitor.activo) {
      const {inf, NOMBRE} = analizarMonitor(d.hx.slice(-200), d.hy.slice(-200), 0.01, a.generales.monitor);
      const me = inf.metricas;
      monitor.estado = NOMBRE[inf.estado];
      monitor.gravedad = inf.estado;
      monitor.metricas = {muestras: me.muestras, maxAbs: r3(me.maxAbs), maxSalto: r3(me.maxSalto), maxVelocidad: r3(me.maxVelocidad),
        maxAceleracion: r3(me.maxAceleracion), cambiosSigno: r3(me.cambiosSigno), noNumericos: me.noNumericos};
      monitor.eventos = inf.eventos.slice(0, 8).map(e => ({g: NOMBRE[e.g], a: e.g === 2, i: e.i, eje: e.eje, motivo: e.motivo,
        v: isFinite(e.v) ? r3(e.v) : null, lim: r3(e.lim)}));
      monitor.mas = Math.max(inf.eventos.length - 8, 0) + inf.omitidos;
    }
    return JSON.stringify({
      diag: {on: g.encendida, ap: g.aplicando, forma: g.forma, t: r3(g.tamano), hz: r3(g.hz), e: r3(g.entradaMs), c: r3(g.ceder),
        lim: g.limitada, ramp: r3(g.rampa), ces: r3(g.cesion), amp: r3(g.amplitud), fase: r3(g.fase), tr: g.enTransicion,
        hx: ultimas(d.hx), hy: ultimas(d.hy), ha: ultimas(d.ha)},
      monitor,
      entrada: estado(d.entrada), salida: estado(d.salida),
      mando: "DualSense", esp: true, envios: m.envios,
      mandoRitmo: {hz: m.hz, huecoMs: redondear(m.huecoMs), conexion: "USB"},
      bateria: {porcentaje: m.bateria, estado: m.estado},
      funciones: resumenFunciones(p, a.generales, d.ar, d.ay),
      bucle: {vueltas: this.vueltasSeg, peorMs: redondear(this.peorSeg * 10) / 10},
      pausado: this.pausado, antiRecoil: d.ar, ayuda: d.ay,
      aviso: this.aviso,
      widgets: p.widgets.map(w => estadoWidget(w, p, d.ar, d.ay, this.pausado)).filter(Boolean),
      rev: this.rev(),
      perfil: {nombre: p.nombre, color: p.color},
    });
  }
  perfilJson() {
    const a = this.almacen, p = a.activo(), generales = clon(a.generales);
    delete generales.clave;
    delete generales.servidorMovil;
    return {
      perfiles: a.perfiles.map(p => ({id: p.id, nombre: p.nombre, color: p.color})),
      activo: a.activoId, perfil: p, generales, pausado: this.pausado,
      capacidades: ["manual", "placa"],
      catalogo: catalogoWidgets(p).map(w => ({tipo: w.tipo, objetivo: w.objetivo || "", nombre: nombreWidget(w, p)})),
      rev: this.rev(),
    };
  }
  alternarWidget(id) {
    const a = this.almacen, w = a.activo().widgets.find(w => w.id === id);
    if (!w) return false;
    switch (w.tipo) {
      case "antiRecoil": this.pedidos.push("ar"); break;
      case "ayuda": this.pedidos.push("ay"); break;
      case "pausa": this.pausado = !this.pausado; break;
      case "turbos": a.alternarTurbos(); break;
      case "macros": a.alternarMacros(); break;
      case "turbo": return w.objetivo !== undefined && a.alternarTurbo(w.objetivo) !== null;
      case "macro": return w.objetivo !== undefined && a.alternarMacro(w.objetivo) !== null;
    }
    return true;
  }
  aplicar(accion) {
    const s = k => (typeof accion[k] === "string" ? accion[k] : null), a = this.almacen;
    let info = null, error = null;
    switch (s("accion")) {
      case "poner":
        if (s("ruta") === null || accion.valor === undefined) error = "falta la ruta o el valor";
        else error = a.ponerRuta(s("ruta"), accion.valor);
        break;
      case "perfil": if (s("id") === null) error = "perfil no válido"; else a.seleccionar(s("id")); break;
      case "situaciones": {
        const n = a.crearPerfilesPorSituacion();
        info = n === 0 ? "Ya existen «Corto alcance» y «Largo alcance»" : "Añadidos " + n + " perfil" + (n === 1 ? "" : "es");
        break;
      }
      case "medidorBorrar": this.medidor.borrar(); break;
      case "cambiarClave": error = demoNo("cambiar la clave"); break;
      case "patron":
        if (!Number.isInteger(accion.indice) || accion.indice < 0) error = "patrón no válido"; else a.usarPatronAyuda(accion.indice);
        break;
      case "variante":
        switch (s("modo")) {
          case "usar": if (s("id") === null) error = "variante no válida"; else a.usarVarianteAyuda(s("id")); break;
          case "guardar": a.conActivo(p => guardarVariante(p.ayuda, s("nombre") || "")); break;
          case "actualizar": a.conActivo(p => actualizarVariante(p.ayuda)); break;
          case "borrar": if (s("id") === null) error = "variante no válida"; else a.conActivo(p => borrarVariante(p.ayuda, s("id"))); break;
          default: error = "modo desconocido";
        }
        break;
      case "nuevo": a.nuevo(); break;
      case "duplicar": a.duplicar(); break;
      case "borrar": a.borrarActivo(); break;
      case "pausa": this.pausado = accion.valor === true; break;
      case "widget":
        if (s("id") === null) error = "widget no válido";
        else if (!this.alternarWidget(s("id"))) error = "Ese widget ya no existe";
        break;
      case "widgetAnadir":
        if (s("tipo") === "basicos") widgetsBasicos(a.activo()).forEach(w => a.anadirWidget(w));
        else if (TIPOS.includes(s("tipo"))) a.anadirWidget(widget(s("tipo"), s("objetivo") || undefined));
        else error = "widget no válido";
        break;
      case "widgetQuitar": if (s("id") === null) error = "widget no válido"; else a.quitarWidget(s("id")); break;
      case "widgetMover":
        if (s("id") === null || !Number.isInteger(accion.paso)) error = "widget no válido"; else a.moverWidget(s("id"), accion.paso);
        break;
      case "servidorMovil": error = "En la placa el acceso por la red está siempre encendido"; break;
      default: error = "acción desconocida";
    }
    const r = error === null ? {ok: true, rev: this.rev()} : {ok: false, error, rev: this.rev()};
    if (info !== null) r.info = info;
    return r;
  }
}

// ---------- Estado inicial de la demo ----------
function perfilesIniciales() {
  const normal = nuevo("perfil", {nombre: "Normal", color: "#0050FF"});
  const zombis = nuevo("perfil", {
    nombre: "Zombis", color: "#00C853",
    der: {sensX: 110, sensY: 105},
    antiRecoil: {activo: true, vertical: 22},
    ayuda: {activo: true, variantes: [{nombre: "Suave para escopeta", base: 1, forma: "circulo", tamano: 6, hz: 10, entradaMs: 200, ceder: 75}]},
    turbos: [{boton: "r2", hz: 12, ciclo: 50, activo: false}],
    macros: [{nombre: "Dropshot", activa: false, disparador: "r2", bloquearDisparador: false, pasos: [{botones: ["circulo"], ms: 600}]}],
  });
  aplicarPatron(zombis.ayuda, 1);
  zombis.widgets = widgetsBasicos(zombis);
  const campana = nuevo("perfil", {
    nombre: "Campaña", color: "#FFB300",
    der: {curva: 1.3},
    antiRecoil: {activo: true, vertical: 26, progresivo: true, verticalFinal: 14, transicionMs: 1200},
  });
  aplicarPatron(campana.ayuda, 3);
  campana.widgets = widgetsBasicos(campana);
  const franco = nuevo("perfil", {
    nombre: "Francotirador", color: "#FF2D2D", enCiclo: false,
    der: {sensX: 80, sensY: 80, curva: 1.6, suavizado: 15},
    l2: {disparoRapido: true},
    reasignar: {r3: "circulo", circulo: "r3"},
    ayuda: {activo: true},
  });
  aplicarPatron(franco.ayuda, 0);
  franco.widgets = [widget("ayuda"), widget("pausa")];
  return [[normal, zombis, campana, franco], zombis.id];
}
// Ráfagas de antes (ayer y hoy) para que «Mi control» no empiece vacío; las nuevas salen del mando simulado
function historialInicial(medidor) {
  let semilla = 20261111;
  const rnd = () => { semilla = (semilla + 0x6D2B79F5) | 0; let t = Math.imul(semilla ^ (semilla >>> 15), 1 | semilla); t ^= t + Math.imul(t ^ (t >>> 7), 61 | t); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const hoy = new Date(), ayer = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate() - 1, 21, 40);
  const fechas = [];
  for (let i = 0; i < 7; i++) fechas.push(ayer.getTime() / 1000 + i * 95 + rnd() * 40);
  for (let i = 0; i < 9; i++) fechas.push(hoy.getTime() / 1000 - 1800 + i * 150 + rnd() * 60);
  fechas.forEach((f, k) => {
    const n = Math.round((0.6 + rnd() * 1.4) / 0.01), reaccion = rnd() < 0.12 ? -1 : 12 + Math.floor(rnd() * 20);
    const bajada = 0.1 + rnd() * 0.12, deriva = (rnd() - 0.42) * 0.12, x = [], abajo = [];
    for (let i = 0; i < n; i++) {
      const tira = reaccion < 0 ? 0.03 * rnd() : i < reaccion ? 0.04 * rnd() : bajada * (1 - Math.exp(-(i - reaccion) / 9)) + 0.025 * Math.sin(i * 0.8 + k);
      abajo.push(Math.fround(tira));
      x.push(Math.fround(deriva * i / n + 0.02 * Math.sin(i * 0.45 + k)));
    }
    medidor.anadir(analizarRafaga(x, abajo, k < 7 ? "Campaña" : "Zombis", f - DESDE_2001), x, abajo);
  });
}

const [perfiles, activoId] = perfilesIniciales();
const generales = nuevo("generales");
generales.medidor.activo = true;   // en la demo, «Mi control» ya está midiendo
const medidor = new Medidor();
historialInicial(medidor);
const motor = new Nucleo(new Almacen(perfiles, activoId, generales), medidor);

// ---------- Wifi y placa (main/red.c, main/web.c) ----------
const QR_DEMO = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 37 37\" shape-rendering=\"crispEdges\"><rect width=\"37\" height=\"37\" fill=\"#fff\"/><path d=\"M4,4h1v1h-1zM5,4h1v1h-1zM6,4h1v1h-1zM7,4h1v1h-1zM8,4h1v1h-1zM9,4h1v1h-1zM10,4h1v1h-1zM12,4h1v1h-1zM14,4h1v1h-1zM15,4h1v1h-1zM16,4h1v1h-1zM17,4h1v1h-1zM18,4h1v1h-1zM19,4h1v1h-1zM24,4h1v1h-1zM26,4h1v1h-1zM27,4h1v1h-1zM28,4h1v1h-1zM29,4h1v1h-1zM30,4h1v1h-1zM31,4h1v1h-1zM32,4h1v1h-1zM4,5h1v1h-1zM10,5h1v1h-1zM12,5h1v1h-1zM13,5h1v1h-1zM17,5h1v1h-1zM18,5h1v1h-1zM19,5h1v1h-1zM23,5h1v1h-1zM26,5h1v1h-1zM32,5h1v1h-1zM4,6h1v1h-1zM6,6h1v1h-1zM7,6h1v1h-1zM8,6h1v1h-1zM10,6h1v1h-1zM12,6h1v1h-1zM13,6h1v1h-1zM16,6h1v1h-1zM17,6h1v1h-1zM18,6h1v1h-1zM26,6h1v1h-1zM28,6h1v1h-1zM29,6h1v1h-1zM30,6h1v1h-1zM32,6h1v1h-1zM4,7h1v1h-1zM6,7h1v1h-1zM7,7h1v1h-1zM8,7h1v1h-1zM10,7h1v1h-1zM13,7h1v1h-1zM14,7h1v1h-1zM15,7h1v1h-1zM18,7h1v1h-1zM19,7h1v1h-1zM23,7h1v1h-1zM24,7h1v1h-1zM26,7h1v1h-1zM28,7h1v1h-1zM29,7h1v1h-1zM30,7h1v1h-1zM32,7h1v1h-1zM4,8h1v1h-1zM6,8h1v1h-1zM7,8h1v1h-1zM8,8h1v1h-1zM10,8h1v1h-1zM12,8h1v1h-1zM15,8h1v1h-1zM16,8h1v1h-1zM17,8h1v1h-1zM19,8h1v1h-1zM21,8h1v1h-1zM22,8h1v1h-1zM23,8h1v1h-1zM26,8h1v1h-1zM28,8h1v1h-1zM29,8h1v1h-1zM30,8h1v1h-1zM32,8h1v1h-1zM4,9h1v1h-1zM10,9h1v1h-1zM13,9h1v1h-1zM15,9h1v1h-1zM16,9h1v1h-1zM17,9h1v1h-1zM18,9h1v1h-1zM21,9h1v1h-1zM24,9h1v1h-1zM26,9h1v1h-1zM32,9h1v1h-1zM4,10h1v1h-1zM5,10h1v1h-1zM6,10h1v1h-1zM7,10h1v1h-1zM8,10h1v1h-1zM9,10h1v1h-1zM10,10h1v1h-1zM12,10h1v1h-1zM14,10h1v1h-1zM16,10h1v1h-1zM18,10h1v1h-1zM20,10h1v1h-1zM22,10h1v1h-1zM24,10h1v1h-1zM26,10h1v1h-1zM27,10h1v1h-1zM28,10h1v1h-1zM29,10h1v1h-1zM30,10h1v1h-1zM31,10h1v1h-1zM32,10h1v1h-1zM18,11h1v1h-1zM22,11h1v1h-1zM24,11h1v1h-1zM4,12h1v1h-1zM7,12h1v1h-1zM8,12h1v1h-1zM9,12h1v1h-1zM10,12h1v1h-1zM11,12h1v1h-1zM12,12h1v1h-1zM16,12h1v1h-1zM17,12h1v1h-1zM18,12h1v1h-1zM19,12h1v1h-1zM20,12h1v1h-1zM23,12h1v1h-1zM25,12h1v1h-1zM28,12h1v1h-1zM30,12h1v1h-1zM31,12h1v1h-1zM32,12h1v1h-1zM5,13h1v1h-1zM6,13h1v1h-1zM8,13h1v1h-1zM9,13h1v1h-1zM12,13h1v1h-1zM13,13h1v1h-1zM15,13h1v1h-1zM16,13h1v1h-1zM18,13h1v1h-1zM22,13h1v1h-1zM23,13h1v1h-1zM24,13h1v1h-1zM27,13h1v1h-1zM28,13h1v1h-1zM30,13h1v1h-1zM31,13h1v1h-1zM6,14h1v1h-1zM8,14h1v1h-1zM10,14h1v1h-1zM11,14h1v1h-1zM12,14h1v1h-1zM16,14h1v1h-1zM18,14h1v1h-1zM21,14h1v1h-1zM27,14h1v1h-1zM28,14h1v1h-1zM30,14h1v1h-1zM4,15h1v1h-1zM7,15h1v1h-1zM9,15h1v1h-1zM11,15h1v1h-1zM14,15h1v1h-1zM16,15h1v1h-1zM18,15h1v1h-1zM19,15h1v1h-1zM21,15h1v1h-1zM23,15h1v1h-1zM24,15h1v1h-1zM25,15h1v1h-1zM26,15h1v1h-1zM28,15h1v1h-1zM32,15h1v1h-1zM5,16h1v1h-1zM10,16h1v1h-1zM11,16h1v1h-1zM12,16h1v1h-1zM15,16h1v1h-1zM17,16h1v1h-1zM18,16h1v1h-1zM21,16h1v1h-1zM24,16h1v1h-1zM25,16h1v1h-1zM26,16h1v1h-1zM32,16h1v1h-1zM6,17h1v1h-1zM7,17h1v1h-1zM8,17h1v1h-1zM9,17h1v1h-1zM11,17h1v1h-1zM12,17h1v1h-1zM14,17h1v1h-1zM16,17h1v1h-1zM21,17h1v1h-1zM22,17h1v1h-1zM24,17h1v1h-1zM26,17h1v1h-1zM27,17h1v1h-1zM28,17h1v1h-1zM29,17h1v1h-1zM31,17h1v1h-1zM32,17h1v1h-1zM7,18h1v1h-1zM8,18h1v1h-1zM9,18h1v1h-1zM10,18h1v1h-1zM11,18h1v1h-1zM14,18h1v1h-1zM15,18h1v1h-1zM18,18h1v1h-1zM19,18h1v1h-1zM23,18h1v1h-1zM29,18h1v1h-1zM30,18h1v1h-1zM32,18h1v1h-1zM6,19h1v1h-1zM9,19h1v1h-1zM13,19h1v1h-1zM17,19h1v1h-1zM18,19h1v1h-1zM20,19h1v1h-1zM27,19h1v1h-1zM30,19h1v1h-1zM32,19h1v1h-1zM6,20h1v1h-1zM8,20h1v1h-1zM9,20h1v1h-1zM10,20h1v1h-1zM16,20h1v1h-1zM19,20h1v1h-1zM21,20h1v1h-1zM23,20h1v1h-1zM24,20h1v1h-1zM27,20h1v1h-1zM4,21h1v1h-1zM5,21h1v1h-1zM6,21h1v1h-1zM7,21h1v1h-1zM8,21h1v1h-1zM11,21h1v1h-1zM14,21h1v1h-1zM15,21h1v1h-1zM22,21h1v1h-1zM23,21h1v1h-1zM24,21h1v1h-1zM28,21h1v1h-1zM29,21h1v1h-1zM30,21h1v1h-1zM31,21h1v1h-1zM4,22h1v1h-1zM5,22h1v1h-1zM7,22h1v1h-1zM10,22h1v1h-1zM11,22h1v1h-1zM12,22h1v1h-1zM14,22h1v1h-1zM16,22h1v1h-1zM17,22h1v1h-1zM18,22h1v1h-1zM20,22h1v1h-1zM23,22h1v1h-1zM28,22h1v1h-1zM32,22h1v1h-1zM4,23h1v1h-1zM5,23h1v1h-1zM6,23h1v1h-1zM7,23h1v1h-1zM8,23h1v1h-1zM11,23h1v1h-1zM12,23h1v1h-1zM17,23h1v1h-1zM19,23h1v1h-1zM20,23h1v1h-1zM23,23h1v1h-1zM24,23h1v1h-1zM27,23h1v1h-1zM28,23h1v1h-1zM29,23h1v1h-1zM30,23h1v1h-1zM4,24h1v1h-1zM5,24h1v1h-1zM6,24h1v1h-1zM10,24h1v1h-1zM13,24h1v1h-1zM14,24h1v1h-1zM15,24h1v1h-1zM17,24h1v1h-1zM22,24h1v1h-1zM23,24h1v1h-1zM24,24h1v1h-1zM25,24h1v1h-1zM26,24h1v1h-1zM27,24h1v1h-1zM28,24h1v1h-1zM29,24h1v1h-1zM30,24h1v1h-1zM31,24h1v1h-1zM12,25h1v1h-1zM15,25h1v1h-1zM16,25h1v1h-1zM17,25h1v1h-1zM20,25h1v1h-1zM21,25h1v1h-1zM22,25h1v1h-1zM24,25h1v1h-1zM28,25h1v1h-1zM29,25h1v1h-1zM4,26h1v1h-1zM5,26h1v1h-1zM6,26h1v1h-1zM7,26h1v1h-1zM8,26h1v1h-1zM9,26h1v1h-1zM10,26h1v1h-1zM12,26h1v1h-1zM13,26h1v1h-1zM16,26h1v1h-1zM17,26h1v1h-1zM19,26h1v1h-1zM20,26h1v1h-1zM23,26h1v1h-1zM24,26h1v1h-1zM26,26h1v1h-1zM28,26h1v1h-1zM29,26h1v1h-1zM4,27h1v1h-1zM10,27h1v1h-1zM12,27h1v1h-1zM14,27h1v1h-1zM15,27h1v1h-1zM16,27h1v1h-1zM17,27h1v1h-1zM20,27h1v1h-1zM22,27h1v1h-1zM23,27h1v1h-1zM24,27h1v1h-1zM28,27h1v1h-1zM29,27h1v1h-1zM31,27h1v1h-1zM4,28h1v1h-1zM6,28h1v1h-1zM7,28h1v1h-1zM8,28h1v1h-1zM10,28h1v1h-1zM12,28h1v1h-1zM13,28h1v1h-1zM15,28h1v1h-1zM16,28h1v1h-1zM17,28h1v1h-1zM19,28h1v1h-1zM20,28h1v1h-1zM21,28h1v1h-1zM23,28h1v1h-1zM24,28h1v1h-1zM25,28h1v1h-1zM26,28h1v1h-1zM27,28h1v1h-1zM28,28h1v1h-1zM31,28h1v1h-1zM4,29h1v1h-1zM6,29h1v1h-1zM7,29h1v1h-1zM8,29h1v1h-1zM10,29h1v1h-1zM12,29h1v1h-1zM13,29h1v1h-1zM14,29h1v1h-1zM15,29h1v1h-1zM18,29h1v1h-1zM20,29h1v1h-1zM22,29h1v1h-1zM25,29h1v1h-1zM29,29h1v1h-1zM30,29h1v1h-1zM31,29h1v1h-1zM4,30h1v1h-1zM6,30h1v1h-1zM7,30h1v1h-1zM8,30h1v1h-1zM10,30h1v1h-1zM14,30h1v1h-1zM15,30h1v1h-1zM16,30h1v1h-1zM17,30h1v1h-1zM20,30h1v1h-1zM22,30h1v1h-1zM23,30h1v1h-1zM25,30h1v1h-1zM27,30h1v1h-1zM28,30h1v1h-1zM29,30h1v1h-1zM31,30h1v1h-1zM32,30h1v1h-1zM4,31h1v1h-1zM10,31h1v1h-1zM14,31h1v1h-1zM19,31h1v1h-1zM25,31h1v1h-1zM27,31h1v1h-1zM28,31h1v1h-1zM29,31h1v1h-1zM30,31h1v1h-1zM32,31h1v1h-1zM4,32h1v1h-1zM5,32h1v1h-1zM6,32h1v1h-1zM7,32h1v1h-1zM8,32h1v1h-1zM9,32h1v1h-1zM10,32h1v1h-1zM12,32h1v1h-1zM18,32h1v1h-1zM20,32h1v1h-1zM21,32h1v1h-1zM22,32h1v1h-1zM23,32h1v1h-1zM24,32h1v1h-1zM26,32h1v1h-1zM28,32h1v1h-1zM29,32h1v1h-1z\" fill=\"#000\"/></svg>";  // qr::svg("http://puente.local/#k=DEMO"), el mismo código que dibuja la placa
const wifi = {
  sta: {ssid: "Casa", configurada: true, conectada: true, ip: "192.168.1.50", rssi: -54, conectando: false, error: null},
  ap: {ssid: "p5k-ps5 DEMO", abierta: true, activa: false, siempre: false, ip: "192.168.4.1", clientes: 0},
  redes: [["Casa", -52, true], ["Ático 2B", -66, true], ["Vecinos_5G", -71, true], ["MiFibra-7C21", -78, true], ["Invitados", -83, false]]
    .map(([ssid, rssi, segura]) => ({ssid, rssi, segura})),
  buscando: false,
};
function wifiJson() {
  wifi.sta.rssi = -54 + Math.round((Math.random() - 0.5) * 4);
  return {sta: clon(wifi.sta), ap: clon(wifi.ap), redes: clon(wifi.redes), buscando: wifi.buscando,
    direcciones: ["http://puente.local", "http://192.168.1.50"], porRedPropia: false, modo: "consola", mandoReal: true, firmware: "demo"};
}
function wifiPost(o) {
  switch (o && o.accion) {
    case "buscar":
      if (wifi.buscando) return {ok: false, error: "No se pudo buscar redes ahora; prueba otra vez en unos segundos"};
      wifi.buscando = true;
      wifi.redes = [];
      setTimeout(() => {
        wifi.redes = [["Casa", -52, true], ["Ático 2B", -66, true], ["Vecinos_5G", -71, true], ["MiFibra-7C21", -78, true],
          ["Invitados", -83, false], ["Impresora-DIRECT", -88, true]]
          .map(([ssid, rssi, segura]) => ({ssid, rssi: rssi + Math.round((Math.random() - 0.5) * 6), segura}))
          .sort((a, b) => b.rssi - a.rssi);
        wifi.buscando = false;
      }, 2400);
      return {ok: true};
    case "conectar": return {ok: false, error: demoNo("conectar la placa a otra wifi")};
    case "olvidar": return {ok: false, error: demoNo("olvidar la wifi")};
    case "ap": return {ok: false, error: demoNo("cambiar la red propia")};
    case "modo": return {ok: false, error: demoNo("cambiar el modo")};
    case "reiniciar": return {ok: false, error: demoNo("reiniciar")};
    default: return {ok: false, error: o && o.accion ? "acción desconocida" : "petición no válida"};
  }
}
const directos = new Set();
function movilJson(k) {
  const direcciones = ["http://puente.local", "http://192.168.1.50"].map(d => d + "/#k=" + encodeURIComponent(k));
  return {direcciones, qr: k === CLAVE ? QR_DEMO : null, clientes: Math.max(directos.size, 1), puerto: 80, activo: true, local: false};
}

// ---------- El reloj: el motor da una vuelta por cada milisegundo ----------
const T0 = CICLO;   // empieza al principio de un ciclo: en un segundo ya está apuntando
const inicio = performance.now() / 1000;
let simT = T0;
function avanzar() {
  const destinoT = T0 + performance.now() / 1000 - inicio;
  if (destinoT - simT > 0.25) simT = destinoT - 0.25;   // la pestaña estuvo dormida: no se recupera todo
  while (simT + 0.001 <= destinoT) {
    simT += 0.001;
    motor.vuelta(entradaSimulada(simT), simT);
  }
  motor.lento();
}
avanzar();
setInterval(() => {
  avanzar();
  if (directos.size) {
    const datos = motor.instantanea();
    for (const es of directos) es._emitir(new MessageEvent("message", {data: datos, origin: location.origin}));
  }
}, 50);

// ---------- La red: fetch, EventSource y XMLHttpRequest ----------
const RUTAS = new Set(["/perfil", "/estado", "/medidor", "/movil", "/api", "/wifi", "/firmware", "/eventos", "/icono.png"]);
function rutaDemo(u) {
  try {
    const x = new URL(u, location.href);
    return x.origin === location.origin && RUTAS.has(x.pathname) ? x : null;
  } catch (e) { return null; }
}
const responder = (cuerpo, estado, tipo) => new Response(typeof cuerpo === "string" ? cuerpo : JSON.stringify(cuerpo),
  {status: estado || 200, headers: {"Content-Type": tipo || "application/json; charset=utf-8", "Cache-Control": "no-store"}});
const texto = (t, estado) => responder(t, estado, "text/plain; charset=utf-8");
function leerCuerpo(c) { try { const v = JSON.parse(c); return v && typeof v === "object" && !Array.isArray(v) ? v : null; } catch (e) { return null; } }
const fetchOriginal = window.fetch.bind(window);
function atender(url, metodo, init) {
  const k = url.searchParams.get("k");
  if (!k) return texto("Falta la clave", 401);   // en la demo vale cualquier clave
  if (metodo === "POST") {
    const h = new Headers((init && init.headers) || {});
    if (h.get("X-Puente") !== "1") return responder({ok: false, error: "petición no válida"}, 400);
  }
  const cuerpo = () => leerCuerpo(init && typeof init.body === "string" ? init.body : "");
  switch (metodo + " " + url.pathname) {
    case "GET /perfil": return responder(motor.perfilJson());
    case "GET /estado": return responder(motor.instantanea());
    case "GET /medidor": return responder(motor.medidor.json());
    case "GET /movil": return responder(movilJson(k));
    case "POST /api": { const o = cuerpo(); return responder(o ? motor.aplicar(o) : {ok: false, error: "petición no válida"}); }
    case "GET /wifi": return responder(wifiJson());
    case "POST /wifi": return responder(wifiPost(cuerpo()));
    case "POST /firmware": return responder({ok: false, error: demoNo("grabar firmware")});
  }
  return texto("No existe", 404);
}
window.fetch = function (entrada, init) {
  const url = rutaDemo(typeof entrada === "string" || entrada instanceof URL ? entrada : entrada && entrada.url);
  if (!url) return fetchOriginal(entrada, init);
  if (url.pathname === "/icono.png") return fetchOriginal(new URL("icono.png", location.href), init);
  const metodo = String((init && init.method) || (entrada instanceof Request ? entrada.method : "GET")).toUpperCase();
  const senal = init && init.signal;
  return new Promise((ok, mal) => {
    if (senal && senal.aborted) { mal(new DOMException("La petición se ha cancelado", "AbortError")); return; }
    // Un poco de espera, como por la wifi
    setTimeout(() => { try { ok(atender(url, metodo, init)); } catch (e) { mal(e); } }, 15 + Math.random() * 30);
  });
};

const EventSourceOriginal = window.EventSource;
class EventSourceDemo extends EventTarget {
  constructor(u, opciones) {
    super();
    const url = rutaDemo(u);
    if (!url || url.pathname !== "/eventos") return new EventSourceOriginal(u, opciones);
    this.url = url.href; this.withCredentials = false; this.readyState = 0;
    this.onopen = null; this.onmessage = null; this.onerror = null;
    setTimeout(() => {
      if (this.readyState === 2) return;
      if (!url.searchParams.get("k")) { this.readyState = 2; this._emitir(new Event("error")); return; }
      this.readyState = 1;
      this._emitir(new Event("open"));
      directos.add(this);
      this._emitir(new MessageEvent("message", {data: motor.instantanea(), origin: location.origin}));
    }, 30);
  }
  _emitir(ev) {
    if (this.readyState === 2 && ev.type === "message") return;
    this.dispatchEvent(ev);
    const f = this["on" + ev.type];
    if (typeof f === "function") f.call(this, ev);
  }
  close() { this.readyState = 2; directos.delete(this); }
}
EventSourceDemo.CONNECTING = 0; EventSourceDemo.OPEN = 1; EventSourceDemo.CLOSED = 2;
window.EventSource = EventSourceDemo;

// La subida del firmware va por XMLHttpRequest (para la barra de progreso): en la demo se contesta que no
const XHROriginal = window.XMLHttpRequest;
class XHRDemo extends XHROriginal {
  open(metodo, u, ...resto) {
    this._demo = rutaDemo(u);
    if (!this._demo) return super.open(metodo, u, ...resto);
    this._estado = 0; this._texto = ""; this._subida = {onprogress: null}; this._listo = false;
  }
  setRequestHeader(k, v) { if (!this._demo) super.setRequestHeader(k, v); }
  get upload() { return this._demo ? this._subida : super.upload; }
  get status() { return this._demo ? this._estado : super.status; }
  get responseText() { return this._demo ? this._texto : super.responseText; }
  get readyState() { return this._demo ? (this._listo ? 4 : 1) : super.readyState; }
  send(cuerpo) {
    if (!this._demo) return super.send(cuerpo);
    setTimeout(() => {
      this._estado = 200;
      this._texto = JSON.stringify({ok: false, error: demoNo("grabar firmware")});
      this._listo = true;
      this.dispatchEvent(new ProgressEvent("load"));
      this.dispatchEvent(new ProgressEvent("loadend"));
    }, 300);
  }
}
window.XMLHttpRequest = XHRDemo;

// La página deja la clave en la dirección con «/#k=…» (la raíz de la placa); aquí la página vive en /demo/
const reemplazar = history.replaceState.bind(history);
history.replaceState = function (estado, titulo, url) {
  if (typeof url === "string" && url.startsWith("/#")) url = location.pathname + location.search + url.slice(1);
  return reemplazar(estado, titulo, url);
};
// Arranca sin pedir la clave. Con «#tab=sticks» (o «#k=…&tab=sticks») se abre en esa pestaña.
const pestana = location.hash.match(/[#&]tab=([a-z]+)/);
if (pestana) { try { localStorage.setItem("tab", pestana[1]); } catch (e) {} }
if (!/[#&]k=[^&]/.test(location.hash)) reemplazar(null, "", location.pathname + location.search + "#k=" + CLAVE);
})();
