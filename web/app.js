// p5k-ps5 · la web. El mapa del mando: cada control enseña lo que la placa hace con él.
// Los textos salen de la propia app (app/Pagina.swift), para no prometer nada que no haga.
"use strict";

const ZONAS = {
  r2: {
    etq: [652, 22, "i"],
    nombre: "R2", resumen: "Tu gatillo de disparar.",
    funciones: [
      { n: "Anti-recoil", d: "Baja el stick derecho mientras disparas, con la fuerza que eliges. Puede cambiar durante la ráfaga, llevar algo de horizontal y esperar antes de empezar.", sc: true },
      { n: "A fondo al rozar", d: "Al rozarlo cuenta como pulsado a fondo." },
      { n: "Recorrido", d: "El recorrido inicial que no cuenta y desde dónde cuenta como pulsado a fondo." },
    ],
  },
  l2: {
    etq: [-12, 22, "d"],
    nombre: "L2", resumen: "Tu gatillo de apuntar.",
    funciones: [
      { n: "Ayuda al apuntado", d: "Mientras apuntas, mueve el stick derecho en círculos o temblores diminutos para que la ayuda del propio juego no se suelte. Con patrones, variantes y un monitor de la señal.", sc: true },
      { n: "A fondo al rozar", d: "Al rozarlo cuenta como pulsado a fondo." },
      { n: "Recorrido", d: "El recorrido inicial que no cuenta y desde dónde cuenta como pulsado a fondo." },
    ],
  },
  r1: {
    etq: [652, 62, "i"],
    nombre: "L1 y R1", resumen: "Y cualquier otro botón.",
    funciones: [
      { n: "Turbo", d: "Mientras mantienes el botón, la consola lo recibe pulsándose y soltándose solo, a la velocidad que eliges." },
      { n: "Reasignar", d: "Elige qué recibe la consola al pulsar cada botón de tu mando." },
    ],
  },
  dcho: {
    etq: [652, 252, "i"],
    nombre: "Stick derecho", resumen: "La mira.",
    funciones: [
      { n: "Zona muerta", d: "Lo poco que se mueve sin hacer nada. Súbela si la mira se mueve sola." },
      { n: "Anti zona muerta", d: "Salta la zona muerta del propio juego para que responda al primer roce." },
      { n: "Curva y suavizado", d: "Con el stick casi a tope, la sensibilidad sube poco a poco. El suavizado quita tirones y temblores." },
    ],
  },
  izdo: {
    etq: [-12, 252, "d"],
    nombre: "Stick izquierdo", resumen: "El movimiento.",
    funciones: [
      { n: "Zona muerta", d: "Súbela si el personaje se mueve solo." },
      { n: "Alcance", d: "Lo más lejos que llega el stick a la consola, y desde dónde cuenta como a tope." },
      { n: "Intercambiar sticks", d: "El izquierdo hace de derecho y al revés." },
    ],
  },
  botones: {
    etq: [652, 150, "i"],
    nombre: "Botones", resumen: "△ ○ ✕ □ y todos los demás.",
    funciones: [
      { n: "Reasignar", d: "Elige qué recibe la consola al pulsar cada botón de tu mando." },
      { n: "Pulsación larga", d: "Una cosa al tocarlo y otra al mantenerlo. La corta se envía al soltar el botón." },
      { n: "Alternar", d: "Una pulsación equivale a mantenerlo pulsado, hasta la siguiente." },
    ],
  },
  cruceta: {
    etq: [-12, 150, "d"],
    nombre: "Cruceta", resumen: "O el botón que quieras como disparador.",
    funciones: [
      { n: "Macros", d: "Pulsan una secuencia de botones al pulsar su disparador. Cada paso dice qué botones se pulsan y durante cuánto tiempo." },
      { n: "Dropshot y jumpshot", d: "Macros hechas que se disparan con tu botón de disparar, sin bloquearlo.", sc: true },
    ],
  },
  panel: {
    etq: [320, -14, "c", 320, 80],
    nombre: "Panel táctil", resumen: "Tus perfiles.",
    funciones: [
      { n: "Perfiles", d: "Un perfil por juego, cada uno con todos sus ajustes. Se cambia en un toque desde el móvil." },
      { n: "Luz del mando", d: "Cada perfil pone su color en la luz del DualSense." },
    ],
  },
  ps: {
    etq: [320, 356, "c", 320, 244],
    nombre: "Combinaciones", resumen: "Sin soltar el mando.",
    funciones: [
      { n: "Encender y apagar", d: "Activa o quita una función con una combinación de botones. La luz del DualSense destella verde al encender y roja al apagar." },
      { n: "Cambiar de patrón", d: "Pasa al siguiente patrón de la ayuda al apuntado con una combinación, y sale un aviso con su nombre.", sc: true },
    ],
  },
};

// La pantalla de la demo donde se ajusta cada control
const PANTALLA = { r2: "Anti-recoil", l2: "Ayuda al apuntado", r1: "Turbo", dcho: "Sticks", izdo: "Sticks",
                   botones: "Botones", cruceta: "Macros", panel: "Perfiles", ps: "En vivo" };

const h = (etiqueta, attrs = {}, ...hijos) => {
  const e = document.createElement(etiqueta);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
  for (const c of hijos.flat()) e.append(c);
  return e;
};

function funcion(f) {
  return h("li", { class: "tz-funcion" },
    h("h3", {}, f.n),
    h("p", {}, f.d),
    f.sc ? h("span", { class: "sin-conexion" }, "Solo sin conexión") : "");
}

function mapa() {
  const raiz = document.querySelector("[data-mapa]");
  if (!raiz) return;
  const detalle = raiz.querySelector("[data-detalle]");
  const puntos = [...raiz.querySelectorAll(".punto")];
  const formas = [...raiz.querySelectorAll(".mando-dibujo > :not(.guias) [data-z], .mando-dibujo > [data-z]")];

  const guias = raiz.querySelector("[data-guias]");
  const mando = raiz.querySelector(".mando");
  const ayuda = raiz.querySelector(".mapa-ayuda");
  const NS = "http://www.w3.org/2000/svg";
  for (const p of puntos) {
    const z = ZONAS[p.dataset.zona];
    p.dataset.nombre = z.nombre;
    p.setAttribute("aria-label", `${z.nombre}: ${z.resumen}`);
    // Llamada de plano: del control sube o baja hasta la altura del nombre y sigue en horizontal
    const x = +p.style.getPropertyValue("--x"), y = +p.style.getPropertyValue("--y");
    // Las llamadas verticales (panel, combinaciones) salen del borde de la pieza, no de su centro: así no cruzan el mando
    const [lx, ly, al, x0 = x, y0 = y] = z.etq;
    const linea = document.createElementNS(NS, "polyline");
    linea.setAttribute("points", al === "c" ? `${x0},${y0} ${lx},${ly + (ly < y ? 8 : -8)}` : `${x},${y} ${x},${ly} ${lx},${ly}`);
    linea.dataset.z = p.dataset.zona;
    guias.append(linea);
    const nombre = h("span", { class: "etq", "data-al": al, "data-zona": p.dataset.zona, "aria-hidden": "true",
                               style: `--x:${lx};--y:${ly}` }, z.nombre);
    mando.append(nombre);
  }
  const etiquetas = [...raiz.querySelectorAll(".etq")];
  formas.push(...guias.querySelectorAll("[data-z]"));

  function elegir(id, foco) {
    const z = ZONAS[id];
    for (const p of puntos) p.setAttribute("aria-pressed", String(p.dataset.zona === id));
    for (const f of formas) f.classList.toggle("activa", f.dataset.z === id);
    for (const e of etiquetas) e.classList.toggle("activa", e.dataset.zona === id);
    ayuda.replaceChildren(h("b", {}, z.nombre), " · toca otra parte del mando");
    detalle.replaceChildren(
      h("div", { class: "tz-cab" },
        h("span", { class: "tz-control" }, z.nombre),
        h("p", { class: "tz-resumen" }, z.resumen)),
      h("ul", { class: "tz-funciones" }, z.funciones.map(funcion)),
      h("button", { class: "tz-demo", type: "button", "data-ir": PANTALLA[id] }, `Ajústalo en la demo: ${PANTALLA[id]}`));
    if (foco) foco.focus();
  }

  raiz.addEventListener("click", (e) => {
    const p = e.target.closest(".punto, .etq");
    if (p) elegir(p.dataset.zona);
  });
  // Flechas para recorrer los controles con el teclado
  raiz.addEventListener("keydown", (e) => {
    const i = puntos.indexOf(document.activeElement);
    if (i < 0 || !["ArrowRight", "ArrowDown", "ArrowLeft", "ArrowUp"].includes(e.key)) return;
    e.preventDefault();
    const paso = e.key === "ArrowRight" || e.key === "ArrowDown" ? 1 : -1;
    const sig = puntos[(i + paso + puntos.length) % puntos.length];
    elegir(sig.dataset.zona, sig);
  });
  elegir("r2");
}

function lista() {
  const caja = document.querySelector("[data-lista]");
  if (!caja) return;
  caja.replaceChildren(...Object.entries(ZONAS).map(([id, z]) =>
    h("div", { class: "grupo" },
      h("h3", { class: "grupo-t" }, z.nombre),
      h("ul", {}, z.funciones.map((f) =>
        h("li", {}, f.n, f.sc ? h("span", { class: "marca-sc" }, "· solo sin conexión") : ""))),
      h("button", { class: "tz-demo grupo-ir", type: "button", "data-ir": PANTALLA[id] }, `En la demo: ${PANTALLA[id]}`))));
}

function pestanas() {
  const tabs = [...document.querySelectorAll('[role="tab"]')];
  if (!tabs.length) return;
  function activar(t, foco) {
    for (const o of tabs) {
      const sel = o === t;
      o.setAttribute("aria-selected", String(sel));
      o.tabIndex = sel ? 0 : -1;
      document.getElementById(o.getAttribute("aria-controls")).hidden = !sel;
    }
    if (foco) t.focus();
  }
  tabs.forEach((t, i) => {
    t.addEventListener("click", () => activar(t));
    t.addEventListener("keydown", (e) => {
      if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
      e.preventDefault();
      activar(tabs[(i + (e.key === "ArrowRight" ? 1 : -1) + tabs.length) % tabs.length], true);
    });
  });
}

// Identificadores de las pestañas de la app (TABS en app/Pagina.swift), para abrir la demo en una
const TAB_DEMO = { "En vivo": "vivo", "Sticks": "sticks", "Gatillos": "gatillos", "Botones": "botones", "Turbo": "turbo",
                   "Macros": "macros", "Anti-recoil": "antirecoil", "Ayuda al apuntado": "ayuda", "Perfiles": "perfiles" };

// La demo: la lista de la izquierda lleva la app (mismo origen) a cada pantalla, y al revés
function demo() {
  const marco = document.querySelector("[data-demo]");
  const saltos = [...document.querySelectorAll("[data-saltos] button")];
  if (!marco || !saltos.length) return;
  let pendiente = null;
  const marcar = (nombre) => {
    for (const b of saltos) b.setAttribute("aria-pressed", String(b.dataset.ir === nombre));
  };
  const pestana = (nombre) => {
    const doc = marco.contentDocument;
    return doc && [...doc.querySelectorAll("#tabs button")].find((b) => b.textContent.trim() === nombre);
  };
  // Mientras la demo arranca no hay pestañas todavía: se reintenta unos segundos
  const ir = (nombre, intentos = 24) => {
    const t = pestana(nombre);
    if (t) { t.click(); marcar(nombre); pendiente = null; }
    else if (intentos > 0) { pendiente = nombre; setTimeout(() => pendiente === nombre && ir(nombre, intentos - 1), 250); }
  };
  for (const b of saltos) b.addEventListener("click", () => ir(b.dataset.ir));
  // Desde el mapa de la portada: baja a la demo y abre la pantalla del control (en el móvil, la demo a pantalla completa)
  document.addEventListener("click", (e) => {
    const b = e.target.closest(".tz-demo");
    if (!b) return;
    if (getComputedStyle(marco).display === "none") {
      location.href = "demo/#k=DEMO&tab=" + encodeURIComponent(TAB_DEMO[b.dataset.ir] || "vivo");
      return;
    }
    document.getElementById("demo").scrollIntoView({ behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
    marco.loading = "eager";
    ir(b.dataset.ir);
  });
  marco.addEventListener("load", () => {
    const doc = marco.contentDocument;
    doc?.addEventListener("click", (e) => {
      const t = e.target.closest?.("#tabs button");
      if (t) marcar(t.textContent.trim());
    });
  });
}

mapa();
lista();
pestanas();
demo();
