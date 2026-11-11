// p5k-ps5 · la web: pestañas de la guía y la demo. El mando 3D vive en escena.js.
"use strict";

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
  marco.addEventListener("load", () => {
    marco.contentDocument?.addEventListener("click", (e) => {
      const t = e.target.closest?.("#tabs button");
      if (t) marcar(t.textContent.trim());
    });
  });
}

pestanas();
demo();
