// Visor 3D de las cajas imprimibles (sección de descargas): carga la base y la tapa en STL (los mismos archivos
// que se descargan) y, en la caja de la placa, la placa dentro. Se gira con el dedo o el ratón; «Abrir» levanta
// la tapa. Solo dibuja mientras se ve en pantalla.
import * as THREE from "three";
import { RoomEnvironment } from "./vendor/RoomEnvironment.js";
import { STLLoader } from "./vendor/STLLoader.js";
import { OrbitControls } from "./vendor/OrbitControls.js";
import { cargarPlacaP5k } from "./hardware3d.js";

const quieto = matchMedia("(prefers-reduced-motion: reduce)");

function soportaWebGL() {
  try { return !!document.createElement("canvas").getContext("webgl2"); } catch { return false; }
}

function voltear(g, alto) {
  g.scale(1, 1, -1);
  g.translate(0, 0, alto);
  // Al reflejar, las caras quedan del revés: se cambia el orden de cada triángulo
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i += 3) {
    const x = p.getX(i + 1), y = p.getY(i + 1), z = p.getZ(i + 1);
    p.setXYZ(i + 1, p.getX(i + 2), p.getY(i + 2), p.getZ(i + 2));
    p.setXYZ(i + 2, x, y, z);
  }
  g.computeVertexNormals();
}

async function montar(raiz) {
  const lienzo = raiz.querySelector("canvas");
  const boton = raiz.querySelector("[data-abrir]");
  const render = new THREE.WebGLRenderer({ canvas: lienzo, antialias: true, alpha: true });
  render.setPixelRatio(Math.min(devicePixelRatio, 2));
  render.toneMapping = THREE.ACESFilmicToneMapping;
  render.outputColorSpace = THREE.SRGBColorSpace;
  const escena = new THREE.Scene();
  escena.environment = new THREE.PMREMGenerator(render).fromScene(new RoomEnvironment(), 0.04).texture;
  escena.environmentIntensity = 0.7;
  const luz = new THREE.DirectionalLight(0xffffff, 1.8);
  luz.position.set(60, 120, 80);
  escena.add(luz);
  const contra = new THREE.DirectionalLight(0xff8a5c, 0.6);
  contra.position.set(-80, 40, -60);
  escena.add(contra);

  const cargador = new STLLoader();
  const [gBase, gTapa] = await Promise.all([raiz.dataset.base, raiz.dataset.tapa].map((u) => cargador.loadAsync(u)));
  // Las tapas se descargan como se imprimen (boca abajo, en la cama): aquí se les da la vuelta para montarlas
  voltear(gTapa, +raiz.dataset.alto);
  // El plástico impreso: mate, con un poco de brillo de capa
  const plastico = new THREE.MeshPhysicalMaterial({ color: 0xe9e9e6, roughness: 0.62, clearcoat: 0.15, clearcoatRoughness: 0.7 });
  const tapaMat = plastico.clone();
  const conjunto = new THREE.Group();
  const base = new THREE.Mesh(gBase, plastico);
  const tapa = new THREE.Mesh(gTapa, tapaMat);
  conjunto.add(base, tapa);
  if (raiz.dataset.placa) {
    const { grupo } = await cargarPlacaP5k();
    // La placa en coordenadas de la caja: su centro en (31, 15) y su cara de abajo a la altura del apoyo
    grupo.position.set(31, 15, +raiz.dataset.placa);
    conjunto.add(grupo);
  }
  // Las cajas se diseñan con Z hacia arriba: aquí Y es arriba
  conjunto.rotation.x = -Math.PI / 2;
  const caja = new THREE.Box3().setFromObject(conjunto);
  const centro = caja.getCenter(new THREE.Vector3());
  conjunto.position.sub(centro);
  const pivote = new THREE.Group();
  pivote.add(conjunto);
  escena.add(pivote);
  const tam = caja.getSize(new THREE.Vector3()).length();

  const camara = new THREE.PerspectiveCamera(30, 1, 1, 2000);
  camara.position.set(tam * 0.85, tam * 0.8, tam * 1.15);
  const control = new OrbitControls(camara, lienzo);
  control.enableDamping = true;
  control.enablePan = false;
  control.minDistance = tam * 0.8;
  control.maxDistance = tam * 3;
  control.autoRotate = !quieto.matches;
  control.autoRotateSpeed = 1.2;
  control.addEventListener("start", () => { control.autoRotate = false; });

  let abierta = false, subida = 0, visible = false;
  boton?.addEventListener("click", () => {
    abierta = !abierta;
    boton.setAttribute("aria-pressed", String(abierta));
    boton.textContent = abierta ? "Cerrar" : "Abrir";
  });

  function medir() {
    const r = lienzo.getBoundingClientRect();
    render.setSize(r.width, r.height, false);
    camara.aspect = r.width / r.height;
    camara.updateProjectionMatrix();
  }
  new ResizeObserver(medir).observe(lienzo);
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; }).observe(raiz);
  medir();
  render.setAnimationLoop(() => {
    if (!visible) return;
    subida += ((abierta ? 1 : 0) - subida) * (quieto.matches ? 1 : 0.12);
    tapa.position.z = subida * 22;
    tapaMat.transparent = subida > 0.01;
    tapaMat.opacity = 1 - subida * 0.25;
    control.update();
    render.render(escena, camara);
  });
  raiz.classList.add("listo");
}

if (soportaWebGL()) {
  const visores = [...document.querySelectorAll("[data-visor-caja]")];
  // Se monta cada visor cuando se acerca a la pantalla (los STL y la placa pesan)
  const vigia = new IntersectionObserver((entradas) => {
    for (const e of entradas) if (e.isIntersecting) { vigia.unobserve(e.target); montar(e.target).catch((err) => { console.error(err); e.target.classList.add("sin-visor"); }); }
  }, { rootMargin: "400px" });
  visores.forEach((v) => vigia.observe(v));
} else {
  document.querySelectorAll("[data-visor-caja]").forEach((v) => v.classList.add("sin-visor"));
}
