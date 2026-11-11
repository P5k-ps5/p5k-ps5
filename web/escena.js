// El escenario: el DualSense 3D fijo en pantalla mientras pasan las paradas. El modelo es «Playstation 5
// Dualsense» de AHarmlessPotato (Sketchfab, CC BY 4.0), con las texturas reducidas para la web (modelo/).
// Cada parada tiene una pose (giro, posición, tamaño), las zonas que se iluminan en naranja (un foco sobre la
// superficie, porque el modelo viene en tres piezas grandes) y cuánto se vuelve translúcido para enseñar la
// placa por dentro. Entre paradas la pose se interpola con el scroll; el render solo corre si se ve.
import * as THREE from "three";
import { RoomEnvironment } from "./vendor/RoomEnvironment.js";
import { GLTFLoader } from "./vendor/GLTFLoader.js";
import { crearPlaca } from "./placa3d.js";

const raiz = document.documentElement;
const escenario = document.querySelector(".escenario");
const lienzo = document.querySelector(".lienzo");
const paradas = [...document.querySelectorAll(".parada")];
const indice = [...document.querySelectorAll("[data-ir-parada]")];
const quieto = matchMedia("(prefers-reduced-motion: reduce)");
const SENAL = new THREE.Color(0xff5b1f);
const AZUL = 0x2a52ff;
const COLORES_PERFIL = [0x2a52ff, 0x00c853, 0xff2d55, 0xb04dff, 0xffb300];

// Centro y radio de cada zona en el mando de frente (6,4 unidades de ancho, centrado en el origen)
const ZONAS = {
  l2: [-2.09, 2.1, 0.75], r2: [2.09, 2.1, 0.75],
  izdo: [-1.11, 0, 0.62], dcho: [1.08, 0, 0.62],
  cruceta: [-2.16, 0.94, 0.85], botones: [2.15, 0.96, 0.92],
  panel: [0, 1.5, 1.3],
};

// Poses: rot en radianes (x, y, z), pos en unidades de escena, esc = tamaño relativo, rayos = translucidez
const POSES = [
  { rot: [-0.3, -0.36, 0.05], pos: [2.85, -0.05, 0], esc: 0.72, zonas: [], rayos: 0, movil: { y: 0.01, esc: 0.95 } },
  { rot: [0.78, -0.26, 0.03], pos: [2.45, -0.45, 0], esc: 0.84, zonas: ["l2", "r2"], rayos: 0 },
  { rot: [-0.08, 0.02, 0], pos: [2.4, 0.05, 0], esc: 0.84, zonas: ["izdo", "dcho"], rayos: 0 },
  { rot: [-0.2, -0.38, 0.02], pos: [2.4, 0, 0], esc: 0.86, zonas: ["cruceta", "botones"], rayos: 0 },
  { rot: [-0.08, 0.0, 0], pos: [2.5, 0.1, 0], esc: 0.88, zonas: ["panel"], rayos: 0, luces: true },
  { rot: [-0.3, -0.5, 0.06], pos: [2.35, 0.1, 0], esc: 0.8, zonas: [], rayos: 1, movil: { esc: 0.8, y: 0.24 } },
];

function soportaWebGL() {
  try { return !!document.createElement("canvas").getContext("webgl2"); } catch { return false; }
}

if (!escenario || !lienzo || !soportaWebGL()) {
  raiz.classList.add("sin-3d");
} else {
  iniciar().catch((e) => { console.error(e); raiz.classList.add("sin-3d"); });
}

// Foco naranja sobre la superficie: se añade a la emisión de cada material del modelo
const FOCOS = { uFocos: { value: [new THREE.Vector4(), new THREE.Vector4()] }, uEje: { value: new THREE.Vector3(0, 0, 1) }, uColorFoco: { value: SENAL.clone() }, uFuerza: { value: 0 } };
function conFoco(m) {
  m.onBeforeCompile = (s) => {
    Object.assign(s.uniforms, FOCOS);
    s.vertexShader = s.vertexShader
      .replace("#include <common>", "#include <common>\nvarying vec3 vPosMundo;")
      .replace("#include <project_vertex>", "#include <project_vertex>\nvPosMundo = (modelMatrix * vec4(transformed, 1.0)).xyz;");
    s.fragmentShader = s.fragmentShader
      .replace("#include <common>", "#include <common>\nvarying vec3 vPosMundo;\nuniform vec4 uFocos[2];\nuniform vec3 uEje;\nuniform vec3 uColorFoco;\nuniform float uFuerza;")
      .replace("#include <map_fragment>", `#include <map_fragment>
        float foco = 0.0;
        for (int i = 0; i < 2; i++) {
          if (uFocos[i].w <= 0.0) continue;
          vec3 d = vPosMundo - uFocos[i].xyz;
          vec3 plano = d - dot(d, uEje) * uEje;
          foco = max(foco, 1.0 - smoothstep(uFocos[i].w * 0.5, uFocos[i].w, length(plano)));
        }
        foco *= uFuerza;
        // Tiñe la superficie (en el blanco no bastaría con sumar luz) y la hace brillar un poco
        diffuseColor.rgb = mix(diffuseColor.rgb, uColorFoco * 0.7, clamp(foco * 1.3, 0.0, 1.0));`)
      .replace("#include <emissivemap_fragment>", `#include <emissivemap_fragment>
        totalEmissiveRadiance += uColorFoco * foco * 0.45;`);
  };
  m.needsUpdate = true;
}

async function cargarMando() {
  const gltf = await new GLTFLoader().loadAsync("./modelo/dualsense.gltf");
  const modelo = gltf.scene;
  const materiales = [];
  let luz = null;
  modelo.traverse((o) => {
    if (!o.isMesh) return;
    const m = o.material;
    // Los materiales vienen en modo mezcla: opacos con recorte se ven bien y sin problemas de orden
    m.transparent = false; m.depthWrite = true; m.alphaTest = 0.5;
    if (m.emissiveMap) { luz = m; m.emissive.set(AZUL); m.emissiveIntensity = 2.2; }
    conFoco(m);
    materiales.push(m);
  });
  // Centrado, de frente (la cara de los botones mira a +Z) y a 6,4 unidades de ancho
  const caja = new THREE.Box3().setFromObject(modelo);
  const tam = caja.getSize(new THREE.Vector3());
  const k = 6.4 / tam.x;
  modelo.position.sub(caja.getCenter(new THREE.Vector3()));
  const mando = new THREE.Group();
  const ajuste = new THREE.Group();
  ajuste.add(modelo);
  ajuste.scale.setScalar(k);
  ajuste.rotation.y = Math.PI;
  mando.add(ajuste);
  return { mando, materiales, luz };
}

async function iniciar() {
  const render = new THREE.WebGLRenderer({ canvas: lienzo, antialias: true, alpha: true, powerPreference: "high-performance" });
  render.setPixelRatio(Math.min(devicePixelRatio, 2));
  render.toneMapping = THREE.ACESFilmicToneMapping;
  render.toneMappingExposure = 1.0;
  render.outputColorSpace = THREE.SRGBColorSpace;

  const escena = new THREE.Scene();
  escena.environment = new THREE.PMREMGenerator(render).fromScene(new RoomEnvironment(), 0.04).texture;
  escena.environmentIntensity = 0.75;
  const clave = new THREE.DirectionalLight(0xffffff, 1.6);
  clave.position.set(3, 5, 6);
  escena.add(clave);
  const contra = new THREE.DirectionalLight(0xff8a5c, 0.8);
  contra.position.set(-5, -2, -4);
  escena.add(contra);
  const contorno = new THREE.DirectionalLight(0xffffff, 2.0); // recorta el blanco sobre el negro
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

  const { mando, materiales, luz } = await cargarMando();
  const placa = crearPlaca();
  placa.scale.setScalar(0.001);
  const pivote = new THREE.Group();
  pivote.add(mando, placa);
  escena.add(pivote);

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
    if (!movil) {
      // El mando (6,4 de ancho, algo más con el giro) tiene que caber entero a la derecha del texto
      const x = p.pos[0] * Math.min(1, visibleAncho / 11.5);
      const cabe = (visibleAncho / 2 - x) * 0.84 / 3.5;
      return { ...p, pos: [x, p.pos[1], p.pos[2]], esc: Math.min(p.esc * Math.min(1, visibleAncho / 10.5), cabe) };
    }
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
  const actual = { rot: [...POSES[0].rot], pos: [...POSES[0].pos], esc: 1, rayos: 0, fuerza: 0 };
  let activa = -1, puntero = [0, 0], punteroSuave = [0, 0];
  let visible = true, pendiente = false, t0 = performance.now();
  const centros = [new THREE.Vector3(), new THREE.Vector3()];

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
      rayos: mezcla(a.rayos, b.rayos, t),
      parada: Math.round(f),
    };
  }

  function marcarParada(n) {
    if (n === activa) return;
    activa = n;
    paradas.forEach((p, k) => p.classList.toggle("activa", k === n));
    indice.forEach((a) => a.classList.toggle("activa", +a.dataset.irParada === n));
    actual.fuerza = 0; // el foco nuevo entra desde cero
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
    actual.rayos = mezcla(actual.rayos, obj.rayos, k);

    // Respira un poco en la portada y sigue al puntero
    const vivo = !quieto.matches;
    const seg = ahora / 1000;
    punteroSuave = punteroSuave.map((v, n) => mezcla(v, puntero[n], 1 - Math.pow(0.02, dt)));
    const flota = vivo ? Math.sin(seg * 0.9) * 0.04 : 0;
    pivote.rotation.set(actual.rot[0] + punteroSuave[1] * 0.12 + (vivo ? Math.sin(seg * 0.6) * 0.03 : 0),
      actual.rot[1] + punteroSuave[0] * 0.18, actual.rot[2]);
    pivote.position.set(actual.pos[0], actual.pos[1] + flota, actual.pos[2]);
    pivote.scale.setScalar(actual.esc);
    pivote.updateMatrixWorld(true);
    sombra.position.set(actual.pos[0], actual.pos[1] - 2.5 * actual.esc, -0.5);
    sombra.scale.set(6.6 * actual.esc, 2.3 * actual.esc, 1);
    sombra.material.opacity = 0.7 - flota * 2;

    // Focos naranjas sobre las zonas de la parada, con un pulso lento
    const zonas = POSES[activa]?.zonas || [];
    actual.fuerza = mezcla(actual.fuerza, zonas.length ? 1 : 0, 1 - Math.pow(0.004, dt));
    const pulso = vivo ? 0.8 + Math.sin(seg * 3) * 0.2 : 1;
    FOCOS.uFuerza.value = actual.fuerza * pulso;
    FOCOS.uEje.value.set(0, 0, 1).applyQuaternion(pivote.quaternion);
    for (let i = 0; i < 2; i++) {
      const z = ZONAS[zonas[i]];
      if (!z) { FOCOS.uFocos.value[i].w = 0; continue; }
      centros[i].set(z[0], z[1], 0);
      pivote.localToWorld(centros[i]);
      FOCOS.uFocos.value[i].set(centros[i].x, centros[i].y, centros[i].z, z[2] * actual.esc);
    }

    // Por dentro: la carcasa se vuelve translúcida y aparece la placa
    const r = suave(Math.min(1, Math.max(0, actual.rayos)));
    for (const m of materiales) {
      const translucido = r > 0.01;
      if (m.transparent !== translucido) {
        // Con el recorte puesto, todo lo que baja del 50 % de opacidad desaparecería
        m.transparent = translucido; m.depthWrite = !translucido; m.alphaTest = translucido ? 0 : 0.5; m.needsUpdate = true;
      }
      m.opacity = 1 - r * 0.72;
    }
    placa.scale.setScalar(Math.max(0.001, Math.min(1, (r - 0.2) / 0.6)));

    // La barra de luz pasa por los colores de los perfiles en su parada
    if (luz) {
      const c = new THREE.Color(POSES[activa]?.luces ? COLORES_PERFIL[Math.floor(seg / 1.4) % COLORES_PERFIL.length] : AZUL);
      luz.emissive.lerp(c, 1 - Math.pow(0.01, dt));
    }

    render.render(escena, camara);
    if (visible && (vivo || Math.abs(actual.rayos - obj.rayos) > 0.001)) pedir();
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
