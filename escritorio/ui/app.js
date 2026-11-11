// Asistente de primer arranque: 1) instalar el firmware en la ESP32-S3, 2) P5Mate, 3) resumen.
"use strict";

const tauri = window.__TAURI__;
// Sin Tauri (abrir ui/index.html en un navegador) se usan datos de prueba para ver la interfaz.
const invocar = tauri
  ? tauri.core.invoke
  : async (orden) => {
      if (orden === "listar_puertos") return [{ nombre: "/dev/cu.usbmodem1101", vid: 0x303a, pid: 0x1001, producto: "USB JTAG/serial debug unit", tipo: "esp32s3", descripcion: "ESP32-S3 (USB nativo)" }];
      if (orden === "info_firmware") return { version: "1.0.0", bytes: 350000 };
      if (orden === "instalar_firmware") return { chip: "ESP32-S3", bytes: 350000, verificado: true };
      if (orden === "detectar_modo") return { modo: "consola", puerto: null, confirmado: true };
      if (orden === "preguntar_modo") return "consola";
      if (orden === "direcciones_movil") return ["http://192.168.1.20:8787/#k=ABCDEFGHJK"];
      if (orden === "direccion_panel") return "about:blank";
      return null;
    };
const escuchar = tauri ? tauri.event.listen : async () => () => {};

const $ = (id) => document.getElementById(id);
const CLAVE = "puente-de-mando:asistente";

// ---- estado guardado (si el almacenamiento falla, la app sigue funcionando) ----
function leer() {
  try { return JSON.parse(localStorage.getItem(CLAVE)) || {}; } catch { return {}; }
}
function guardar(cambios) {
  const nuevo = { ...leer(), ...cambios };
  try { localStorage.setItem(CLAVE, JSON.stringify(nuevo)); } catch { /* sin almacenamiento */ }
  return nuevo;
}

// ---- navegación ----
const ORDEN = ["placa", "p5mate", "listo"];
let paso = "placa";
let temporizador = null;

function ir(nuevo) {
  paso = nuevo;
  for (const p of ORDEN) $(`paso-${p}`).hidden = p !== nuevo;
  const e = leer();
  const hecho = { placa: !!e.placa, p5mate: !!e.p5mate, listo: false };
  document.querySelectorAll("#pasos button").forEach((b) => {
    const p = b.dataset.paso;
    b.classList.toggle("actual", p === nuevo);
    b.classList.toggle("hecho", p !== nuevo && hecho[p]);
    b.setAttribute("aria-current", p === nuevo ? "step" : "false");
  });
  clearInterval(temporizador);
  if (nuevo === "placa") {
    buscarPuertos();
    temporizador = setInterval(buscarPuertos, 1500);
  }
  if (nuevo === "listo") { resumen(); direccionesMovil(); }
}

document.querySelectorAll("#pasos button").forEach((b) => b.addEventListener("click", () => ir(b.dataset.paso)));
document.querySelectorAll("[data-ir]").forEach((b) => b.addEventListener("click", () => ir(b.dataset.ir)));

// ---- paso 1: placa ----
let puertos = [];
let elegido = null;
let instalando = false;

function pintarPuertos() {
  const lista = $("lista-puertos");
  lista.replaceChildren();
  for (const p of puertos) {
    const li = document.createElement("li");
    const b = document.createElement("button");
    b.type = "button";
    b.setAttribute("aria-pressed", String(p.nombre === elegido));
    const izq = document.createElement("span");
    const nombre = document.createElement("strong");
    nombre.textContent = p.nombre;
    const detalle = document.createElement("small");
    detalle.textContent = ` · ${p.descripcion}`;
    izq.append(nombre, detalle);
    const etiqueta = document.createElement("span");
    etiqueta.className = "etiqueta" + (p.tipo === "otro" ? " aviso" : "");
    etiqueta.textContent = p.tipo === "otro" ? "No parece una placa" : p.tipo === "firmware" ? "Se actualizará" : "Compatible";
    b.append(izq, etiqueta);
    b.addEventListener("click", () => { if (!instalando) { elegido = p.nombre; pintarPuertos(); actualizarEstado(); } });
    li.append(b);
    lista.append(li);
  }
}

function actualizarEstado() {
  const punto = $("punto-placa");
  const sel = puertos.find((p) => p.nombre === elegido);
  punto.className = "punto " + (sel ? (sel.tipo === "otro" ? "aviso" : "ok") : "espera");
  if (!sel) {
    $("titulo-placa").textContent = "Esperando la placa…";
    $("texto-placa").textContent = "Conéctala ahora. La detecto sola.";
  } else if (sel.tipo === "firmware") {
    $("titulo-placa").textContent = "Placa con el firmware ya instalado";
    $("texto-placa").textContent = "Puedes volver a instalarlo para actualizarlo.";
  } else if (sel.tipo === "otro") {
    $("titulo-placa").textContent = "Dispositivo no reconocido";
    $("texto-placa").textContent = "No parece una ESP32-S3. Si estás seguro, puedes intentarlo.";
  } else {
    $("titulo-placa").textContent = "Placa detectada";
    $("texto-placa").textContent = `${sel.descripcion} en ${sel.nombre}`;
  }
  $("btn-instalar").disabled = !sel || instalando;
}

async function buscarPuertos() {
  if (instalando) return;
  try {
    puertos = await invocar("listar_puertos");
  } catch {
    puertos = [];
  }
  if (!puertos.some((p) => p.nombre === elegido)) {
    const mejor = puertos.find((p) => p.tipo !== "otro");
    elegido = mejor ? mejor.nombre : null;
  }
  pintarPuertos();
  actualizarEstado();
}

function mostrarError(texto) {
  const e = $("error-placa");
  e.textContent = texto || "";
  e.hidden = !texto;
}

function progreso(porcentaje, texto) {
  $("bloque-progreso").hidden = false;
  const barra = $("barra");
  barra.setAttribute("aria-valuenow", String(Math.round(porcentaje)));
  $("barra-relleno").style.transform = `scaleX(${porcentaje / 100})`;
  $("texto-progreso").textContent = texto;
}

$("btn-instalar").addEventListener("click", async () => {
  if (!elegido || instalando) return;
  instalando = true;
  // Si justo se está preguntando el modo por el mismo puerto, se espera a que lo suelte
  while (buscandoModo) await new Promise((r) => setTimeout(r, 100));
  mostrarError("");
  $("btn-instalar").disabled = true;
  $("btn-sig-placa").hidden = true;
  progreso(0, "Empezando…");
  const quitar = await escuchar("instalacion", (ev) => progreso(ev.payload.porcentaje, ev.payload.mensaje));
  try {
    const r = await invocar("instalar_firmware", { puerto: elegido });
    guardar({ placa: true, verificado: r.verificado });
    progreso(100, r.verificado
      ? "Firmware instalado y funcionando. La placa ya se ve como un mando."
      : "Firmware instalado. No he podido comprobar el arranque; si la placa está en modo consola es normal.");
    $("btn-sig-placa").hidden = false;
    $("btn-instalar").textContent = "Instalar de nuevo";
  } catch (e) {
    $("bloque-progreso").hidden = true;
    mostrarError(typeof e === "string" ? e : "No se ha podido instalar el firmware.");
  } finally {
    quitar();
    instalando = false;
    buscarPuertos();
  }
});

$("btn-sig-placa").addEventListener("click", () => ir("p5mate"));
$("btn-saltar-placa").addEventListener("click", () => {
  guardar({ placa: true, saltada: true });
  ir("p5mate");
});

// ---- paso 2: P5Mate ----
async function comprar() {
  try { await invocar("abrir_p5mate"); } catch (e) { alert(String(e)); }
}
$("btn-comprar").addEventListener("click", comprar);
$("btn-comprar-2").addEventListener("click", comprar);
$("btn-luego").addEventListener("click", () => { guardar({ p5mate: "luego" }); ir("listo"); });
$("btn-ya-tengo").addEventListener("click", () => { guardar({ p5mate: "tengo" }); ir("listo"); });

// ---- paso 3: resumen ----
function resumen() {
  const e = leer();
  $("res-placa").className = "punto " + (e.placa ? (e.saltada && !e.verificado ? "aviso" : "ok") : "error");
  $("res-placa-texto").textContent = !e.placa
    ? "Todavía no está instalado."
    : e.saltada && !e.verificado
      ? "Marcado como ya instalado (no lo he comprobado)."
      : "Instalado en la placa.";
  $("res-p5mate").className = "punto " + (e.p5mate === "tengo" ? "ok" : "aviso");
  $("res-p5mate-texto").textContent = e.p5mate === "tengo" ? "Ya lo tienes." : "Pendiente de comprar.";
}

// ---- modo de la placa (PC o consola), en la cabecera y en el resumen ----
const MODOS = {
  pc: { chip: "Modo PC", titulo: "Modo PC", texto: "Mando y puerto serie por el mismo cable: para usarla con el ordenador. LED verde." },
  consola: { chip: "Modo consola", titulo: "Modo consola", texto: "Solo mando, lista para conectarla al P5Mate. LED cian." },
  grabacion: { chip: "Sin firmware", titulo: "Placa sin firmware", texto: "La placa está en modo grabación o todavía no tiene el firmware. Instálalo en el paso «Placa»." },
  com: { chip: "Placa por el COM", titulo: "Placa conectada por el puerto COM", texto: "Por el puerto COM el modo no se ve a simple vista: hay que preguntárselo a la placa." },
  ninguna: { chip: "Sin placa", titulo: "No hay ninguna placa conectada", texto: "Conecta la ESP32-S3 por USB para ver en qué modo está." },
};
let modoActual = null;
let buscandoModo = false;

function pintarModo(m) {
  const info = MODOS[m.modo] || MODOS.ninguna;
  const dudoso = m.modo === "consola" && !m.confirmado;
  const clase = dudoso ? "aviso" : m.modo === "pc" || m.modo === "consola" ? m.modo : m.modo === "ninguna" ? "" : "aviso";

  const chip = $("chip-modo");
  chip.className = "chip-modo " + (dudoso ? "" : m.modo);
  chip.querySelector(".punto").className = "punto " + clase;
  chip.querySelector("span").textContent = dudoso ? "¿Modo consola?" : info.chip;

  $("modo-punto").className = "punto " + clase;
  $("modo-titulo").textContent = dudoso ? "Hay un mando de PS4, pero no sé si es la placa" : info.titulo;
  $("modo-texto").textContent = dudoso
    ? "Si es la placa, está en modo consola. Si tienes un DualShock 4 conectado, desconéctalo para salir de dudas."
    : info.texto;
  // Por el COM la respuesta no se actualiza sola (cambia si se pulsa BOOT): se deja el botón para repetir.
  $("modo-com").hidden = !(m.modo === "com" || m.porCom);
  $("btn-preguntar").textContent = m.porCom ? "Consultar de nuevo" : "Consultar el modo";
}

async function buscarModo() {
  if (buscandoModo || instalando) return;
  buscandoModo = true;
  try {
    const m = await invocar("detectar_modo");
    if (m.modo !== "com") {
      modoActual = m;
      pintarModo(m);
    } else if (modoActual?.puerto === m.puerto && modoActual.preguntado) {
      // Ya se le preguntó por este COM: se mantiene la respuesta (el botón permite repetir)
      pintarModo({ ...modoActual, modo: modoActual.preguntado, confirmado: true, porCom: true });
    } else if (modoActual?.puerto !== m.puerto || modoActual.modo !== "com") {
      // Puerto COM nuevo: se le pregunta una vez sin esperar a que se pulse el botón
      modoActual = m;
      pintarModo(m);
      await preguntarPorCom();
    }
  } catch {
    /* se reintenta en la siguiente vuelta */
  } finally {
    buscandoModo = false;
  }
}

async function preguntarPorCom() {
  if (!modoActual?.puerto) return;
  const boton = $("btn-preguntar");
  boton.disabled = true;
  $("modo-com-nota").textContent = "Preguntando a la placa…";
  try {
    const respuesta = await invocar("preguntar_modo", { puerto: modoActual.puerto });
    modoActual = { ...modoActual, preguntado: respuesta };
    $("modo-com-nota").textContent = "";
    pintarModo({ ...modoActual, modo: respuesta, confirmado: true, porCom: true });
  } catch (e) {
    $("modo-com-nota").textContent = typeof e === "string" ? e : "La placa no ha contestado.";
  } finally {
    boton.disabled = false;
  }
}

$("btn-preguntar").addEventListener("click", async () => {
  if (buscandoModo) return;
  buscandoModo = true;
  try { await preguntarPorCom(); } finally { buscandoModo = false; }
});

// ---- el panel (la misma página del móvil, servida por esta app) y la dirección para el móvil ----
async function abrirPanel() {
  try {
    location.href = await invocar("direccion_panel");
  } catch (e) {
    const err = $("error-panel");
    err.textContent = typeof e === "string" ? e : "No he podido abrir el panel.";
    err.hidden = false;
  }
}
$("btn-panel").addEventListener("click", abrirPanel);

async function direccionesMovil() {
  const lista = $("direcciones");
  let dirs = [];
  try { dirs = await invocar("direcciones_movil"); } catch { /* sin red */ }
  lista.replaceChildren();
  if (!dirs.length) {
    const li = document.createElement("li");
    li.className = "nota";
    li.textContent = "No encuentro la red de casa. Conecta este ordenador a la wifi o por cable.";
    lista.append(li);
    return;
  }
  for (const d of dirs) {
    const li = document.createElement("li");
    const code = document.createElement("code");
    code.textContent = d;
    const b = document.createElement("button");
    b.type = "button";
    b.className = "secundario";
    b.textContent = "Copiar";
    b.addEventListener("click", async () => {
      try { await navigator.clipboard.writeText(d); b.textContent = "Copiada"; } catch { b.textContent = "Selecciónala"; }
    });
    li.append(code, b);
    lista.append(li);
  }
}

// ---- arranque ----
(async () => {
  try {
    const info = await invocar("info_firmware");
    $("nota-version").textContent = `Firmware ${info.version} · ${(info.bytes / 1024).toFixed(0)} KB`;
  } catch { /* la versión es solo informativa */ }
  const e = leer();
  // El menú «Puente» trae aquí con #placa, #p5mate o #listo; sin nada, si ya está todo listo, se va al panel
  const pedido = location.hash.slice(1);
  if (["placa", "p5mate", "listo"].includes(pedido)) ir(pedido);
  else if (e.placa && e.p5mate && tauri) { abrirPanel(); return; }
  else ir(!e.placa ? "placa" : !e.p5mate ? "p5mate" : "listo");
  window.addEventListener("hashchange", () => { const h = location.hash.slice(1); if (ORDEN.includes(h)) ir(h); });
  buscarModo();
  setInterval(buscarModo, 2000);
})();
