// El escenario: el DualSense 3D fijo en pantalla mientras pasan las paradas. El modelo es «Playstation 5
// Dualsense» de AHarmlessPotato (Sketchfab, CC BY 4.0), con las texturas reducidas para la web (modelo/).
// Cada parada tiene una pose (giro, posición, tamaño) y las zonas que se iluminan en naranja (un foco sobre la
// superficie, porque el modelo viene en tres piezas grandes). En las dos últimas, el mando se aparta y aparece
// el hardware, que va FUERA del mando y unido a él por cable: la placa p5k-ps5 o el montaje con módulos.
// Entre paradas la pose se interpola con el scroll; el render solo corre si se ve.
import * as THREE from "three";
import { RoomEnvironment } from "./vendor/RoomEnvironment.js";
import { GLTFLoader } from "./vendor/GLTFLoader.js";
import { cargarPlacaP5k, crearModulos } from "./hardware3d.js";

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

// Poses: rot en radianes (x, y, z), pos en unidades de escena, esc = tamaño relativo; conjunto = mando + hardware
const POSES = [
  { rot: [-0.3, -0.36, 0.05], pos: [2.85, -0.05, 0], esc: 0.72, zonas: [], movil: { y: 0.01, esc: 0.95 } },
  { rot: [0.78, -0.26, 0.03], pos: [2.45, -0.45, 0], esc: 0.84, zonas: ["l2", "r2"] },
  { rot: [-0.08, 0.02, 0], pos: [2.4, 0.05, 0], esc: 0.84, zonas: ["izdo", "dcho"] },
  { rot: [-0.2, -0.38, 0.02], pos: [2.4, 0, 0], esc: 0.86, zonas: ["cruceta", "botones"] },
  { rot: [-0.08, 0.0, 0], pos: [2.5, 0.1, 0], esc: 0.88, zonas: ["panel"], luces: true },
  { rot: [-0.32, -0.3, 0.02], pos: [2.55, 0.0, 0], esc: 0.95, zonas: [], conjunto: 1, hw: "placa", movil: { esc: 0.82 } },
  { rot: [-0.32, -0.3, 0.02], pos: [2.55, 0.0, 0], esc: 0.95, zonas: [], conjunto: 1, hw: "modulos", movil: { esc: 0.78 } },
];

POSES.forEach((p, i) => { p.indice = i; });

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
  const pivote = new THREE.Group();
  pivote.add(mando);
  escena.add(pivote);

  // El hardware, fuera del mando: debajo de él en el conjunto, a escala (62 mm de placa ≈ 3,4 unidades)
  // Escala y sitio de cada hardware bajo el mando, y altura del mando en el conjunto
  const HW = { placa: { esc: 0.052, y: -1.25, mando: 1.45 }, modulos: { esc: 0.04, y: -1.55, mando: 1.75 } };
  const [placaP5k, modulos] = await Promise.all([cargarPlacaP5k(), Promise.resolve(crearModulos())]);
  const hw = { placa: placaP5k, modulos };
  for (const h of Object.values(hw)) {
    h.grupo.rotation.x = -0.25;
    h.grupo.scale.setScalar(0.0001);
    h.grupo.visible = false;
    pivote.add(h.grupo);
    h.v = 0;
  }
  // Los cables: del USB-C del mando (arriba, en el centro) al puerto MANDO, y del CONSOLA hacia el P5Mate
  const matCable = new THREE.MeshStandardMaterial({ color: 0x1c1d21, roughness: 0.6 });
  const cableMando = new THREE.Mesh(new THREE.BufferGeometry(), matCable);
  const cableConsola = new THREE.Mesh(new THREE.BufferGeometry(), matCable);
  escena.add(cableMando, cableConsola);
  const puertoMando = new THREE.Vector3(0, 2.02, -0.2); // en el mando de 6,4 de ancho

  let ancho = 0, alto = 0, movil = false;
  function medir() {
    const r = lienzo.getBoundingClientRect();
    ancho = r.width; alto = r.height; movil = ancho < 900;
    render.setSize(ancho, alto, false);
    huecos.length = 0;
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
    // En el móvil, el mando se centra en el hueco libre de su parada y se ajusta a él
    const [arriba, abajo] = hueco(p.indice);
    const porPx = visibleAlto / alto;
    const centro = (0.5 - (arriba + abajo) / 2 / alto) * visibleAlto;
    const altoHueco = (abajo - arriba) * porPx;
    // El mando de frente mide 6,4 × 4,2; girado ocupa algo más de alto
    const esc = Math.min((visibleAncho * 0.9) / 6.4, (altoHueco * 0.86) / 4.4) * ((p.movil || {}).esc ?? 1);
    return { ...p, pos: [0, centro, 0], esc };
  }

  // Hueco libre (en píxeles desde arriba de la pantalla) para el mando en cada parada del móvil:
  // en la portada, entre el titular y el texto de abajo; en el resto, entre la barra y el título
  const huecos = [];
  function hueco(i) {
    if (huecos[i]) return huecos[i];
    const par = paradas[i];
    const nav = document.querySelector(".nav")?.offsetHeight || 60;
    let arriba = nav + 8, abajo = alto * 0.5;
    if (par) {
      if (i === 0) {
        const h1 = par.querySelector("h1"), pie = par.querySelector(".portada-pie");
        if (h1) arriba = h1.offsetTop + h1.offsetHeight + 8;
        if (pie) abajo = pie.offsetTop - 8;
      } else {
        const primero = par.firstElementChild;
        if (primero) abajo = primero.offsetTop - 10;
      }
    }
    if (abajo - arriba < alto * 0.22) abajo = arriba + alto * 0.22;
    return (huecos[i] = [arriba, abajo]);
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
  const actual = { rot: [...POSES[0].rot], pos: [...POSES[0].pos], esc: 1, conjunto: 0, fuerza: 0 };
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
      conjunto: mezcla(a.conjunto || 0, b.conjunto || 0, t),
      hw: t < 0.5 ? a.hw : b.hw,
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
    actual.conjunto = mezcla(actual.conjunto, obj.conjunto, k);

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

    // Fuera del mando: el mando sube y se encoge, y debajo aparece el hardware de la parada, unido por cable
    const c = suave(Math.min(1, Math.max(0, actual.conjunto)));
    const kh = 1 - Math.pow(0.004, dt);
    let alturaMando = 0;
    for (const [nombre, h] of Object.entries(hw)) {
      h.v = mezcla(h.v, obj.hw === nombre ? c : 0, kh);
      h.grupo.visible = h.v > 0.01;
      h.grupo.scale.setScalar(Math.max(0.0001, HW[nombre].esc * suave(Math.min(1, h.v))));
      h.grupo.position.set(0.15, HW[nombre].y - (1 - h.v) * 0.6, 0.3);
      alturaMando += HW[nombre].mando * h.v;
    }
    mando.position.set(0, alturaMando, 0);
    mando.scale.setScalar(1 - 0.5 * c);
    const activo = (hw.modulos.v > hw.placa.v ? hw.modulos : hw.placa);
    if (activo.v > 0.05) {
      pivote.updateMatrixWorld(true);
      const p0 = mando.localToWorld(puertoMando.clone());
      const n0 = mando.localToWorld(puertoMando.clone().add(new THREE.Vector3(0, 0.5, 0))).sub(p0);
      const p1 = activo.grupo.localToWorld(activo.puertos.mando.clone());
      const n1 = activo.grupo.localToWorld(activo.puertos.mando.clone().add(activo.puertos.haciaMando.clone().multiplyScalar(14))).sub(p1);
      const lado = new THREE.Vector3(1, 0, 0).applyQuaternion(pivote.quaternion).multiplyScalar(1.15 * actual.esc);
      const curva = new THREE.CatmullRomCurve3([p0, p0.clone().add(n0), p0.clone().add(n0).add(lado.clone().multiplyScalar(1.6)), p1.clone().add(n1).add(lado.clone().multiplyScalar(0.5)), p1.clone().add(n1), p1], false, "centripetal");
      cableMando.geometry.dispose();
      cableMando.geometry = new THREE.TubeGeometry(curva, 80, 0.055 * actual.esc, 10);
      const q0 = activo.grupo.localToWorld(activo.puertos.consola.clone());
      const m0 = activo.grupo.localToWorld(activo.puertos.consola.clone().add(activo.puertos.haciaConsola.clone().multiplyScalar(14))).sub(q0);
      const fuera = q0.clone().add(m0.clone().multiplyScalar(2)).add(new THREE.Vector3(-0.6, -4, 0.4));
      const curva2 = new THREE.CatmullRomCurve3([q0, q0.clone().add(m0), q0.clone().add(m0.clone().multiplyScalar(1.8)).add(new THREE.Vector3(0, -0.6, 0.1)), fuera], false, "centripetal");
      cableConsola.geometry.dispose();
      cableConsola.geometry = new THREE.TubeGeometry(curva2, 48, 0.055 * actual.esc, 10);
    }
    cableMando.visible = cableConsola.visible = activo.v > 0.05;

    // La barra de luz pasa por los colores de los perfiles en su parada
    if (luz) {
      const c = new THREE.Color(POSES[activa]?.luces ? COLORES_PERFIL[Math.floor(seg / 1.4) % COLORES_PERFIL.length] : AZUL);
      luz.emissive.lerp(c, 1 - Math.pow(0.01, dt));
    }

    render.render(escena, camara);
    if (visible && (vivo || Math.abs(actual.conjunto - obj.conjunto) > 0.001)) pedir();
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
