// El escenario: el DualSense 3D fijo en pantalla mientras pasan las paradas. Cada parada tiene una pose
// (giro, posición, tamaño), las zonas que se iluminan en naranja y cuánto se desmonta el mando. Entre paradas
// la pose se interpola con el scroll; el render solo corre mientras el escenario se ve.
import * as THREE from "three";
import { RoomEnvironment } from "./vendor/RoomEnvironment.js";
import { crearMando } from "./mando3d.js";

const raiz = document.documentElement;
const escenario = document.querySelector(".escenario");
const lienzo = document.querySelector(".lienzo");
const paradas = [...document.querySelectorAll(".parada")];
const indice = [...document.querySelectorAll("[data-ir-parada]")];
const quieto = matchMedia("(prefers-reduced-motion: reduce)");
const SENAL = new THREE.Color(0xff5b1f);
const COLORES_PERFIL = [0x2f6bff, 0x00c853, 0xff2d55, 0xb04dff, 0xffb300];

// Poses: rot en radianes (x, y, z), pos en unidades de escena, esc = tamaño relativo
const POSES = [
  { rot: [-0.32, -0.34, 0.06], pos: [2.85, -0.05, 0], esc: 0.72, zonas: [], desmonte: 0, movil: { y: 0.01, esc: 0.95 } },
  { rot: [0.72, -0.28, 0.04], pos: [2.45, -0.4, 0], esc: 0.84, zonas: ["r2", "l2"], desmonte: 0 },
  { rot: [-0.08, 0.02, 0], pos: [2.4, 0.05, 0], esc: 0.84, zonas: ["izdo", "dcho"], desmonte: 0 },
  { rot: [-0.2, -0.38, 0.02], pos: [2.4, 0, 0], esc: 0.86, zonas: ["botones", "cruceta"], desmonte: 0 },
  { rot: [-0.06, 0.0, 0], pos: [2.5, 0.1, 0], esc: 0.88, zonas: ["panel"], desmonte: 0, luces: true },
  { rot: [-0.3, -0.5, 0.06], pos: [2.35, 0.1, 0], esc: 0.72, zonas: [], desmonte: 1, movil: { esc: 0.74, y: 0.24 } },
];

function soportaWebGL() {
  try { return !!document.createElement("canvas").getContext("webgl2"); } catch { return false; }
}

if (!escenario || !lienzo || !soportaWebGL()) {
  raiz.classList.add("sin-3d");
} else {
  iniciar().catch((e) => { console.error(e); raiz.classList.add("sin-3d"); });
}

async function iniciar() {
  const render = new THREE.WebGLRenderer({ canvas: lienzo, antialias: true, alpha: true, powerPreference: "high-performance" });
  render.setPixelRatio(Math.min(devicePixelRatio, 2));
  render.toneMapping = THREE.ACESFilmicToneMapping;
  render.toneMappingExposure = 0.92;
  render.outputColorSpace = THREE.SRGBColorSpace;

  const escena = new THREE.Scene();
  escena.environment = new THREE.PMREMGenerator(render).fromScene(new RoomEnvironment(), 0.04).texture;
  escena.environmentIntensity = 0.55;
  const clave = new THREE.DirectionalLight(0xffffff, 1.9);
  clave.position.set(3, 5, 6);
  escena.add(clave);
  const contra = new THREE.DirectionalLight(0xff8a5c, 0.9);
  contra.position.set(-5, -2, -4);
  escena.add(contra);
  // Luz de contorno: recorta el blanco sobre el negro
  const contorno = new THREE.DirectionalLight(0xffffff, 2.2);
  contorno.position.set(-2, 6, -6);
  escena.add(contorno);

  // Sombra de contacto: un óvalo suave bajo el mando, que no gira con él
  const c2 = document.createElement("canvas");
  c2.width = c2.height = 256;
  const g2 = c2.getContext("2d");
  const grad = g2.createRadialGradient(128, 128, 0, 128, 128, 128);
  grad.addColorStop(0, "rgba(0,0,0,0.75)");
  grad.addColorStop(1, "rgba(0,0,0,0)");
  g2.fillStyle = grad;
  g2.fillRect(0, 0, 256, 256);
  const sombra = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(c2), transparent: true, depthWrite: false }));
  sombra.rotation.x = -Math.PI / 2;
  escena.add(sombra);

  const camara = new THREE.PerspectiveCamera(30, 1, 0.1, 100);
  camara.position.set(0, 0, 13);

  const { mando, zonas, despiece, luces, placa } = crearMando();
  const pivote = new THREE.Group();
  pivote.add(mando);
  escena.add(pivote);

  // Posición de reposo de lo que se desmonta y materiales de cada zona (para iluminarlos)
  for (const [o] of despiece) { o.userData.z0 = o.position.z; o.userData.y0 = o.position.y; }
  const porZona = {};
  for (const [z, objs] of Object.entries(zonas)) {
    porZona[z] = [];
    for (const o of objs) o.traverse((h) => { if (h.isMesh && h.material.emissive && !luces.includes(h)) porZona[z].push(h.material); });
  }

  let ancho = 0, alto = 0, movil = false;
  function medir() {
    const r = lienzo.getBoundingClientRect();
    ancho = r.width; alto = r.height; movil = ancho < 900;
    render.setSize(ancho, alto, false);
    camara.aspect = ancho / alto;
    camara.updateProjectionMatrix();
    pedir();
  }

  // Ajuste de la pose a la pantalla: en el móvil el mando va centrado arriba y más pequeño
  function encajar(p) {
    const visibleAlto = 2 * camara.position.z * Math.tan((camara.fov * Math.PI) / 360);
    const visibleAncho = visibleAlto * camara.aspect;
    if (!movil) return { ...p, pos: [p.pos[0] * Math.min(1, visibleAncho / 11.5), p.pos[1], p.pos[2]], esc: p.esc * Math.min(1, visibleAncho / 10.5) };
    const m = p.movil || {};
    const esc = Math.min(1, (visibleAncho * 0.88) / 6.3) * (m.esc ?? 1);
    return { ...p, pos: [0, visibleAlto * (m.y ?? 0.27), 0], esc: esc * (p.movil ? 1 : 0.86) };
  }

  // Progreso del scroll dentro del escenario: 0 en la portada, N-1 en la última parada
  function progreso() {
    const r = escenario.getBoundingClientRect();
    const total = r.height - innerHeight;
    const p = Math.min(1, Math.max(0, -r.top / Math.max(1, total)));
    return p * (POSES.length - 1);
  }

  const suave = (t) => t * t * (3 - 2 * t);
  const mezcla = (a, b, t) => a + (b - a) * t;
  const actual = { rot: [...POSES[0].rot], pos: [...POSES[0].pos], esc: 1, desmonte: 0 };
  let activa = -1, puntero = [0, 0], punteroSuave = [0, 0];
  let visible = true, pendiente = false, t0 = performance.now();

  function objetivo() {
    const f = progreso();
    const i = Math.min(POSES.length - 2, Math.floor(f));
    // Cada parada se queda quieta un rato antes de pasar a la siguiente
    const t = suave(Math.min(1, Math.max(0, (f - i - 0.3) / 0.55)));
    const a = encajar(POSES[i]), b = encajar(POSES[i + 1]);
    return {
      rot: a.rot.map((v, k) => mezcla(v, b.rot[k], t)),
      pos: a.pos.map((v, k) => mezcla(v, b.pos[k], t)),
      esc: mezcla(a.esc, b.esc, t),
      desmonte: mezcla(a.desmonte, b.desmonte, t),
      parada: Math.round(f),
    };
  }

  function marcarParada(n) {
    if (n === activa) return;
    activa = n;
    paradas.forEach((p, k) => p.classList.toggle("activa", k === n));
    indice.forEach((a) => a.classList.toggle("activa", +a.dataset.irParada === n));
    const z = new Set(POSES[n].zonas);
    for (const [nombre, mats] of Object.entries(porZona)) for (const m of mats) m.userData.objetivo = z.has(nombre) ? 1 : 0;
  }

  function cuadro(ahora) {
    pendiente = false;
    const dt = Math.min(0.05, (ahora - t0) / 1000);
    t0 = ahora;
    const obj = objetivo();
    marcarParada(obj.parada);
    const k = quieto.matches ? 1 : 1 - Math.pow(0.0015, dt); // persecución suave de la pose
    for (let n = 0; n < 3; n++) {
      actual.rot[n] = mezcla(actual.rot[n], obj.rot[n], k);
      actual.pos[n] = mezcla(actual.pos[n], obj.pos[n], k);
    }
    actual.esc = mezcla(actual.esc, obj.esc, k);
    actual.desmonte = mezcla(actual.desmonte, obj.desmonte, k);

    // Respira un poco en la portada y sigue al puntero
    const vivo = !quieto.matches;
    const seg = ahora / 1000;
    punteroSuave = punteroSuave.map((v, n) => mezcla(v, puntero[n], 1 - Math.pow(0.02, dt)));
    const flota = vivo ? Math.sin(seg * 0.9) * 0.04 : 0;
    pivote.rotation.set(actual.rot[0] + punteroSuave[1] * 0.12 + (vivo ? Math.sin(seg * 0.6) * 0.03 : 0),
      actual.rot[1] + punteroSuave[0] * 0.18, actual.rot[2]);
    pivote.position.set(actual.pos[0], actual.pos[1] + flota, actual.pos[2]);
    pivote.scale.setScalar(actual.esc);
    sombra.position.set(actual.pos[0], actual.pos[1] - 2.35 * actual.esc, -0.5);
    sombra.scale.set(6.4 * actual.esc, 2.2 * actual.esc, 1);
    sombra.material.opacity = 0.7 - flota * 2;

    // Desmontar: cada pieza se separa en Z lo suyo
    const d = suave(Math.min(1, Math.max(0, actual.desmonte)));
    for (const [o, dz, dy = 0] of despiece) { o.position.z = o.userData.z0 + dz * d * 0.85; o.position.y = o.userData.y0 + dy * d; }
    placa.scale.setScalar(Math.max(0.001, Math.min(1.25, (d - 0.25) / 0.5 * 1.25)));

    // Zonas en naranja, con un pulso lento
    const pulso = vivo ? 0.75 + Math.sin(seg * 3) * 0.25 : 1;
    for (const mats of Object.values(porZona)) for (const m of mats) {
      m.userData.v = mezcla(m.userData.v || 0, m.userData.objetivo || 0, 1 - Math.pow(0.002, dt));
      m.emissive.copy(SENAL);
      m.emissiveIntensity = m.userData.v * 0.9 * pulso;
    }
    // La barra de luz pasa por los colores de los perfiles en su parada
    const perfil = POSES[activa]?.luces;
    const c = new THREE.Color(perfil ? COLORES_PERFIL[Math.floor(seg / 1.4) % COLORES_PERFIL.length] : 0x1a3cff);
    for (const l of luces) { l.material.emissive.lerp(c, 1 - Math.pow(0.01, dt)); }

    render.render(escena, camara);
    if (visible && (vivo || Math.abs(actual.desmonte - obj.desmonte) > 0.001)) pedir();
  }
  function pedir() { if (!pendiente) { pendiente = true; requestAnimationFrame(cuadro); } }

  new ResizeObserver(medir).observe(lienzo);
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; if (visible) pedir(); }).observe(escenario);
  addEventListener("scroll", pedir, { passive: true });
  addEventListener("pointermove", (e) => {
    if (e.pointerType !== "mouse") return;
    puntero = [(e.clientX / innerWidth) * 2 - 1, (e.clientY / innerHeight) * 2 - 1];
    pedir();
  }, { passive: true });
  // El índice de paradas lleva a cada una
  for (const a of indice) a.addEventListener("click", (e) => {
    e.preventDefault();
    const total = escenario.offsetHeight - innerHeight;
    scrollTo({ top: escenario.offsetTop + (total * +a.dataset.irParada) / (POSES.length - 1), behavior: quieto.matches ? "auto" : "smooth" });
  });

  medir();
  raiz.classList.add("con-3d");
}
