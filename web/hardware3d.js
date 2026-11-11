// Las dos maneras de tener un p5k-ps5, en 3D, para el final del escenario:
// - La placa p5k-ps5: exportada de KiCad (placa/puente.kicad_pcb → modelo/placa.glb) con sus componentes,
//   más las piezas que no tienen modelo en la biblioteca de KiCad (USB-C, MAX3421E, botones y LED), puestas
//   en las mismas coordenadas del diseño (placa/pcb.py).
// - El montaje con módulos: el YD-ESP32-S3 y el MAX3421E mini con las medidas de caja/caja.py (sacadas de
//   fotos de las placas), unidos con los nueve cables Dupont.
// Las dos se construyen en milímetros, con la cara de arriba mirando a +Z y X hacia la derecha; cada una
// devuelve sus puertos (MANDO y CONSOLA) para enganchar los cables.
import * as THREE from "three";
import { GLTFLoader } from "./vendor/GLTFLoader.js";


const mat = {
  metal: new THREE.MeshStandardMaterial({ color: 0xc9ccd2, metalness: 1, roughness: 0.28 }),
  negro: new THREE.MeshStandardMaterial({ color: 0x18191c, roughness: 0.55 }),
  plastico: new THREE.MeshStandardMaterial({ color: 0x0f1012, roughness: 0.7 }),
  oro: new THREE.MeshStandardMaterial({ color: 0xd8b25a, metalness: 1, roughness: 0.3 }),
  blancoLed: new THREE.MeshStandardMaterial({ color: 0xf2f2ee, roughness: 0.4 }),
  pcbNegro: new THREE.MeshPhysicalMaterial({ color: 0x141518, roughness: 0.45, clearcoat: 0.6 }),
  pcbAzul: new THREE.MeshPhysicalMaterial({ color: 0x1d4f9c, roughness: 0.45, clearcoat: 0.6 }),
  serigrafia: new THREE.MeshBasicMaterial({ color: 0xf0f0f0 }),
};

function caja(w, h, d, m, x, y, z) {
  const b = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), m);
  b.position.set(x, y, z);
  return b;
}

// Un rectángulo redondeado extruido (la boca de un USB)
function boca(ancho, alto, largo, radio, m) {
  const s = new THREE.Shape();
  const w = ancho / 2, h = alto / 2, r = Math.min(radio, h);
  s.moveTo(-w + r, -h); s.lineTo(w - r, -h); s.quadraticCurveTo(w, -h, w, -h + r);
  s.lineTo(w, h - r); s.quadraticCurveTo(w, h, w - r, h); s.lineTo(-w + r, h);
  s.quadraticCurveTo(-w, h, -w, h - r); s.lineTo(-w, -h + r); s.quadraticCurveTo(-w, -h, -w + r, -h);
  const hueco = new THREE.Path();
  const wi = w - 0.35, hi = h - 0.35, ri = Math.max(0.2, r - 0.35);
  hueco.moveTo(-wi + ri, -hi); hueco.lineTo(wi - ri, -hi); hueco.quadraticCurveTo(wi, -hi, wi, -hi + ri);
  hueco.lineTo(wi, hi - ri); hueco.quadraticCurveTo(wi, hi, wi - ri, hi); hueco.lineTo(-wi + ri, hi);
  hueco.quadraticCurveTo(-wi, hi, -wi, hi - ri); hueco.lineTo(-wi, -hi + ri); hueco.quadraticCurveTo(-wi, -hi, -wi + ri, -hi);
  s.holes.push(hueco);
  const g = new THREE.ExtrudeGeometry(s, { depth: largo, bevelEnabled: false, curveSegments: 10 });
  g.translate(0, 0, -largo / 2);
  const grupo = new THREE.Group();
  grupo.add(new THREE.Mesh(g, m));
  const fondo = new THREE.Mesh(new THREE.PlaneGeometry(ancho - 0.8, alto - 0.8), mat.plastico);
  fondo.position.z = -largo / 2 + 0.6;
  grupo.add(fondo);
  return grupo;
}

// Gira una boca (ancho en X, alto en Y, abertura hacia +Z) para que quede tumbada en la placa con el ancho a
// lo largo de Y, el alto en Z y la abertura hacia +X (hacia = 1) o -X (hacia = -1)
function orientar(obj, hacia) {
  const m = new THREE.Matrix4().makeBasis(new THREE.Vector3(0, hacia, 0), new THREE.Vector3(0, 0, 1), new THREE.Vector3(hacia, 0, 0));
  obj.quaternion.setFromRotationMatrix(m);
  return obj;
}

// USB-C de montaje superficial con la boca hacia «hacia». Centro en (x, y) de la placa, apoyado en ella
function usbC(x, y, hacia, base = 1.6) {
  const u = orientar(boca(8.94, 3.2, 7.35, 1.6, mat.metal), hacia);
  u.position.set(x, y, base + 3.2 / 2);
  return u;
}

const enGrupo = (grupo, obj, x, y, z) => { obj.position.set(x, y, z); grupo.add(obj); return obj; };

function rotulo(texto, w, h, color, fondo) {
  const c = document.createElement("canvas"); c.width = 512; c.height = Math.max(32, Math.round((512 * h) / w));
  const g = c.getContext("2d");
  if (fondo) { g.fillStyle = fondo; g.fillRect(0, 0, c.width, c.height); }
  g.fillStyle = color; g.textAlign = "center"; g.textBaseline = "middle";
  g.font = `600 ${Math.round(c.height * 0.42)}px ui-monospace, Menlo, monospace`;
  g.fillText(texto, c.width / 2, c.height / 2);
  const t = new THREE.CanvasTexture(c); t.anisotropy = 4; t.colorSpace = THREE.SRGBColorSpace;
  return new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ map: t, transparent: !fondo }));
}

// ------------------------------------------------------------------------------------------------------
// La placa p5k-ps5 (62 × 30 mm)
// ------------------------------------------------------------------------------------------------------
export async function cargarPlacaP5k() {
  const gltf = await new GLTFLoader().loadAsync("./modelo/placa.glb");
  const kicad = gltf.scene;
  // KiCad exporta en metros, con la placa en el plano XZ (Y hacia arriba) y el origen en el de la hoja:
  // la placa empieza en (100, 100) mm. Se pasa a milímetros con la cara de arriba hacia +Z.
  kicad.scale.setScalar(1000);
  kicad.rotation.x = Math.PI / 2;
  kicad.position.set(-100, 100, 0);
  kicad.traverse((o) => {
    if (!o.isMesh) return;
    const m = o.material;
    const hex = m.color.getHexString();
    if (hex === "507c69") { // máscara de soldadura: verde JLCPCB, opaca y por encima del FR4
      o.material = new THREE.MeshPhysicalMaterial({ color: 0x1b5e3b, roughness: 0.42, clearcoat: 0.7, clearcoatRoughness: 0.3, polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -1 });
    } else if (hex === "ffffff") { // serigrafía, por encima de la máscara
      o.material = new THREE.MeshStandardMaterial({ color: 0xf2f2ee, roughness: 0.6, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 });
    } else if (hex === "adb393") { // el FR4, por debajo
      m.polygonOffset = true; m.polygonOffsetFactor = 1; m.polygonOffsetUnits = 1; m.transparent = false; m.opacity = 1;
    } else {
      m.transparent = false; m.opacity = 1;
    }
  });
  const placa = new THREE.Group();
  placa.add(kicad);

  // Lo que no tiene modelo en la biblioteca de KiCad. Coordenadas de placa/pcb.py (mm, Y hacia abajo)
  const enPlaca = (x, y) => [x, -y]; // en el grupo, Y hacia arriba
  const piezas = new THREE.Group();
  const j1 = usbC(...enPlaca(4.0 + 0.3, 9.0), -1);   // CONSOLA, boca a la izquierda
  const j2 = usbC(...enPlaca(58.0 - 0.3, 9.0), 1);   // MANDO, boca a la derecha
  piezas.add(j1, j2);
  const max = caja(5, 5, 1, mat.negro, ...enPlaca(47.0, 13.5), 1.6 + 0.5);
  piezas.add(max);
  const etqMax = rotulo("MAX3421E", 4.4, 1.1, "#c9ccd2");
  etqMax.position.set(...enPlaca(47.0, 13.5), 1.6 + 1.01);
  piezas.add(etqMax);
  for (const y of [26.3, 19.5]) {
    piezas.add(caja(5.1, 5.1, 1.2, mat.metal, ...enPlaca(4.8, y), 1.6 + 0.6));
    const b = new THREE.Mesh(new THREE.CylinderGeometry(1.2, 1.2, 0.7, 24), mat.negro);
    b.rotation.x = Math.PI / 2;
    b.position.set(...enPlaca(4.8, y), 1.6 + 1.5);
    piezas.add(b);
  }
  piezas.add(caja(2, 2, 0.8, mat.blancoLed, ...enPlaca(15.5, 11.5), 1.6 + 0.4));
  placa.add(piezas);

  // Centro de la placa (62 × 30) en el origen
  const centrada = new THREE.Group();
  placa.position.set(-31, 15, 0);
  centrada.add(placa);
  return {
    grupo: centrada,
    puertos: {
      mando: new THREE.Vector3(58.0 - 0.3 + 3.9 - 31, -9.0 + 15, 3.2),
      consola: new THREE.Vector3(4.0 + 0.3 - 3.9 - 31, -9.0 + 15, 3.2),
      haciaMando: new THREE.Vector3(1, 0, 0),
      haciaConsola: new THREE.Vector3(-1, 0, 0),
    },
  };
}

// ------------------------------------------------------------------------------------------------------
// El montaje con módulos: YD-ESP32-S3 (57 × 27,7) y MAX3421E mini (38,3 × 18,5), unidos con nueve cables
// ------------------------------------------------------------------------------------------------------
export function crearModulos() {
  const grupo = new THREE.Group();

  // --- YD-ESP32-S3: placa negra, módulo con blindaje y antena, dos USB-C en un extremo, dos filas de pines
  const esp = new THREE.Group();
  const L = 57.0, A = 27.7, G = 1.6;
  esp.add(caja(L, A, G, mat.pcbNegro, L / 2, 0, G / 2));
  // Módulo ESP32-S3-WROOM-1 (18 × 25,5), con la antena saliendo 6,5 mm por el extremo
  const modX = L - 25.5 / 2 + 6.5;
  esp.add(caja(25.5, 18, 0.8, mat.negro, modX, 0, G + 0.4));
  esp.add(caja(17.6, 15.8, 2.4, mat.metal, modX - 3.6, 0, G + 0.8 + 1.2));
  const etqEsp = rotulo("ESP32-S3", 12, 2.6, "#3a3d44");
  etqEsp.position.set(modX - 3.6, 0, G + 0.8 + 2.41);
  esp.add(etqEsp);
  // Dos USB-C en el extremo de la izquierda, centrados (11,5 mm entre centros), boca hacia -X
  for (const y of [-11.5 / 2, 11.5 / 2]) {
    esp.add(usbC(7.35 / 2 - 0.6, y, -1, G));
  }
  // Botones BOOT y RST, y el LED RGB
  for (const [x, y] of [[28.4, A / 2 - 8.3], [33.8, A / 2 - 8.3]]) {
    esp.add(caja(3.6, 3, 1.2, mat.metal, x, -y, G + 0.6));
    esp.add(caja(1.6, 1.2, 0.8, mat.negro, x, -y, G + 1.4));
  }
  esp.add(caja(2, 2, 0.8, mat.blancoLed, 18.6, A / 2 - 18.5, G + 0.4));
  // Dos filas de 22 pines (2,54 mm) a 25,4 mm: plástico negro por debajo y las puntas hacia abajo
  const filas = [-25.4 / 2, 25.4 / 2];
  for (const y of filas) {
    esp.add(caja(22 * 2.54, 2.5, 2.5, mat.plastico, 2.05 + 21 * 2.54 / 2, y, -1.25));
    for (let i = 0; i < 22; i++) {
      esp.add(caja(0.64, 0.64, 9, mat.oro, 2.05 + i * 2.54, y, -2.5 - 3.6));
      enGrupo(esp, new THREE.Mesh(new THREE.CircleGeometry(0.75, 12), mat.oro), 2.05 + i * 2.54, y, G + 0.01);
    }
  }
  grupo.add(esp);

  // --- MAX3421E mini: placa azul, el chip, el cristal y el USB-A saliendo 7,4 mm por un extremo. Va debajo
  // del ESP32 (en el plano), girado para que su borde de pines mire a la fila de pines del ESP32.
  const max = new THREE.Group();
  const ML = 38.3, MA = 18.5;
  max.add(caja(ML, MA, G, mat.pcbAzul, ML / 2, 0, G / 2));
  const usbA = orientar(boca(13.4, 7.0, 14.0, 0.6, mat.metal), 1);
  usbA.position.set(ML - 14 / 2 + 7.4, 0, G + 3.5);
  max.add(usbA);
  max.add(caja(5, 5, 1, mat.negro, 15, 2, G + 0.5));
  const etqMax = rotulo("MAX3421E", 4.4, 1.1, "#c9ccd2");
  etqMax.position.set(15, 2, G + 1.01);
  max.add(etqMax);
  max.add(caja(4.6, 2, 1.2, mat.metal, 9, -5, G + 0.6)); // cristal de 12 MHz
  const pads = [];
  for (let i = 0; i < 9; i++) { const y = -7.6 + i * 1.9; pads.push([2.2, y]); enGrupo(max, new THREE.Mesh(new THREE.CircleGeometry(0.7, 12), mat.oro), 2.2, y, G + 0.01); }
  // Girado -90°: su X local apunta hacia -Y; el borde de los pads queda arriba, mirando al ESP32
  const MAXX = 14, MAXY = -A / 2 - 20;
  max.rotation.z = -Math.PI / 2;
  max.position.set(MAXX, MAXY, 0);
  grupo.add(max);
  const enMax = ([x, y], z) => new THREE.Vector3(MAXX + y, MAXY - x, z); // local → grupo con el giro de -90°

  // --- Los nueve cables Dupont: de la hembra en cada pin del ESP32 a su pad del MAX, en orden y sin cruzarse,
  // con los colores del montaje probado (GND marrón, 3V3 morado, MISO verde, MOSI amarillo, CLK naranja,
  // SS rojo, INT gris, 5V azul, RST blanco)
  const colores = [0x8a5a3a, 0x9b59d0, 0x33a852, 0xf2d33c, 0xff8a1f, 0xe53935, 0x9e9e9e, 0x2f6bff, 0xf5f5f5];
  const filaY = -25.4 / 2;
  colores.forEach((c, i) => {
    const xPin = 2.05 + (2 + i * 2) * 2.54;            // pines repartidos en la fila de abajo
    const pie = new THREE.Vector3(xPin, filaY, -2.5 - 14); // el final de la hembra Dupont
    const pad = enMax(pads[8 - i], G + 0.3);
    const curva = new THREE.CatmullRomCurve3([
      pie,
      pie.clone().add(new THREE.Vector3(0, -2, -5)),
      new THREE.Vector3((pie.x + pad.x) / 2, (pie.y + pad.y) / 2 - 2, -14 + i * 0.5),
      pad.clone().add(new THREE.Vector3(0, 4, 5)),
      pad,
    ]);
    grupo.add(new THREE.Mesh(new THREE.TubeGeometry(curva, 48, 0.65, 8), new THREE.MeshStandardMaterial({ color: c, roughness: 0.55 })));
    grupo.add(caja(2.5, 2.5, 14, mat.plastico, xPin, filaY, -2.5 - 7)); // la hembra Dupont en el pin
  });

  // Centrado aproximado del conjunto
  const centro = new THREE.Box3().setFromObject(grupo).getCenter(new THREE.Vector3());
  const centrado = new THREE.Group();
  grupo.position.sub(centro);
  centrado.add(grupo);
  return {
    grupo: centrado,
    puertos: {
      // MANDO: la boca del USB-A del MAX (hacia abajo); CONSOLA: el USB-C de arriba del ESP32 (hacia la izquierda)
      mando: enMax([ML + 7.4, 0], G + 3.5).sub(centro),
      consola: new THREE.Vector3(-0.6, 11.5 / 2, G + 1.6).sub(centro),
      haciaMando: new THREE.Vector3(0, -1, 0),
      haciaConsola: new THREE.Vector3(-1, 0, 0),
    },
  };
}
