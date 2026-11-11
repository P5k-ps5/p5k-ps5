// El DualSense en 3D, construido con geometría (sin modelos descargados).
// Las medidas salen del mismo dibujo de frente que el SVG (viewBox 640 × 400): x hacia la derecha, y hacia
// abajo. En 3D, 100 unidades del dibujo son 1 unidad, con el centro del mando en el origen y la cara de los
// botones mirando a +Z. Cada pieza lleva su zona («r2», «dcho», «botones»…) para poder iluminarla.
import * as THREE from "three";

const P = (x, y) => [(x - 320) / 100, -(y - 200) / 100];

// Contorno: mitad izquierda desde arriba-centro hasta abajo-centro; la derecha es su espejo
const ARR = [320, 70];
const IZQ = [
  [[300, 70], [262, 69], [236, 66]],
  [[206, 62], [176, 50], [146, 47]],
  [[108, 44], [76, 56], [60, 84]],
  [[47, 106], [40, 138], [36, 172]],
  [[32, 222], [26, 262], [25, 300]],
  [[24, 342], [46, 372], [80, 373]],
  [[110, 374], [130, 354], [144, 330]],
  [[162, 300], [186, 283], [222, 277]],
  [[256, 271], [292, 270], [320, 270]],
];
const X = (x) => 640 - x;

function forma(ordenes) {
  const s = new THREE.Shape();
  for (const [op, ...pts] of ordenes) {
    const q = pts.map(([x, y]) => P(x, y)).flat();
    if (op === "M") s.moveTo(...q);
    else if (op === "L") s.lineTo(...q);
    else if (op === "C") s.bezierCurveTo(...q);
    else if (op === "Q") s.quadraticCurveTo(...q);
  }
  return s;
}

function contorno() {
  const o = [["M", ARR]];
  for (const [c1, c2, p] of IZQ) o.push(["C", c1, c2, p]);
  const pts = [ARR, ...IZQ.map((s) => s[2])];
  for (let i = IZQ.length - 1; i >= 0; i--) {
    const [c1, c2] = IZQ[i];
    o.push(["C", [X(c2[0]), c2[1]], [X(c1[0]), c1[1]], [X(pts[i][0]), pts[i][1]]]);
  }
  return forma(o);
}

// El núcleo negro: entre las dos alas, desde el borde de arriba hasta abajo, rodeando los sticks
function nucleo() {
  return forma([
    ["M", [232, 178]],
    ["C", [206, 188], [182, 210], [174, 240]],
    ["C", [168, 268], [152, 298], [142, 326]],
    ["C", [164, 298], [188, 282], [222, 276]],
    ["C", [256, 268], [292, 266], [320, 266]],
    ["C", [348, 266], [384, 268], [418, 276]],
    ["C", [452, 282], [476, 298], [498, 326]],
    ["C", [488, 298], [472, 268], [466, 240]],
    ["C", [458, 210], [434, 188], [408, 178]],
    ["Q", [320, 192], [232, 178]],
  ]);
}

function panelTactil() {
  return forma([
    ["M", [224, 72]], ["C", [262, 77], [378, 77], [416, 72]], ["L", [405, 166]],
    ["C", [403, 178], [394, 184], [382, 184]], ["L", [258, 184]],
    ["C", [246, 184], [237, 178], [235, 166]], ["L", [224, 72]],
  ]);
}

function flecha(cx, cy, angulo) {
  const w = 17, l = 24, gap = 10;
  const pts = [[cx - w / 2, cy - gap - l], [cx + w / 2, cy - gap - l], [cx + w / 2, cy - gap - 6], [cx, cy - gap + 2], [cx - w / 2, cy - gap - 6]];
  const a = (angulo * Math.PI) / 180;
  const rot = pts.map(([x, y]) => [cx + (x - cx) * Math.cos(a) - (y - cy) * Math.sin(a), cy + (x - cx) * Math.sin(a) + (y - cy) * Math.cos(a)]);
  return forma([["M", rot[0]], ...rot.slice(1).map((p) => ["L", p]), ["L", rot[0]]]);
}

const extruir = (s, prof, bisel, seg = 4, curva = 48) => {
  const g = new THREE.ExtrudeGeometry(s, {
    depth: prof, bevelEnabled: bisel > 0, bevelThickness: bisel, bevelSize: bisel * 0.9, bevelSegments: seg, curveSegments: curva,
  });
  g.computeVertexNormals();
  return g;
};

export function materiales() {
  return {
    blanco: new THREE.MeshPhysicalMaterial({ color: 0xf1f1ef, roughness: 0.42, clearcoat: 0.35, clearcoatRoughness: 0.5 }),
    mate: new THREE.MeshPhysicalMaterial({ color: 0xebebe8, roughness: 0.7, clearcoat: 0.1, clearcoatRoughness: 0.8 }),
    negro: new THREE.MeshPhysicalMaterial({ color: 0x141416, roughness: 0.55, clearcoat: 0.2, clearcoatRoughness: 0.6 }),
    brillo: new THREE.MeshPhysicalMaterial({ color: 0x0c0c0e, roughness: 0.18, clearcoat: 1, clearcoatRoughness: 0.12 }),
    goma: new THREE.MeshStandardMaterial({ color: 0x1a1a1d, roughness: 0.92 }),
    simbolo: new THREE.MeshStandardMaterial({ color: 0xb9bcc4, roughness: 0.5 }),
    luz: new THREE.MeshStandardMaterial({ color: 0x0a2a6a, emissive: 0x2f6bff, emissiveIntensity: 2.2, roughness: 0.3 }),
  };
}

// Crea el mando. Devuelve el grupo, las piezas de cada zona (para iluminarlas) y lo que se separa al desmontarlo.
export function crearMando() {
  const m = materiales();
  const mando = new THREE.Group();
  const zonas = {};
  const despiece = []; // [objeto, desplazamiento en Z al desmontar]
  const zona = (z, obj) => { (zonas[z] ||= []).push(obj); obj.userData.zona = z; return obj; };
  const malla = (g, mat) => new THREE.Mesh(g, mat.clone ? mat.clone() : mat);

  // Cuerpo blanco (las alas): grosor 0,42 con bisel generoso, para que las empuñaduras se vean redondeadas
  const cuerpo = malla(extruir(contorno(), 0.34, 0.12, 6), m.blanco);
  cuerpo.position.z = -0.12;
  mando.add(cuerpo);
  despiece.push([cuerpo, -0.9]);
  const FRENTE = 0.34; // cara delantera del cuerpo

  // Volumen de detrás: las dos asas de las empuñaduras y el lomo, para que no sea una losa
  for (const lado of [-1, 1]) {
    const asa = malla(new THREE.CapsuleGeometry(0.4, 1.3, 12, 32), m.blanco);
    asa.rotation.set(0.95, 0, lado * 0.24);
    asa.scale.set(0.92, 1, 0.8);
    asa.position.set(lado * 2.3, -0.7, -0.62);
    mando.add(asa);
    despiece.push([asa, -0.9]);
  }
  const lomo = malla(new THREE.SphereGeometry(1, 48, 24), m.blanco);
  lomo.scale.set(2.25, 1.05, 0.42);
  lomo.position.set(0, 0.42, -0.12);
  mando.add(lomo);
  despiece.push([lomo, -0.9]);

  // Núcleo negro en relieve
  const nuc = malla(extruir(nucleo(), 0.03, 0.025, 3), m.negro);
  nuc.position.z = FRENTE;
  mando.add(nuc);
  despiece.push([nuc, -0.35]);
  const NUC = FRENTE + 0.08;

  // Panel táctil y barras de luz
  const panel = zona("panel", malla(extruir(panelTactil(), 0.02, 0.015, 3), m.mate));
  panel.position.z = FRENTE + 0.005;
  mando.add(panel);
  despiece.push([panel, 0.7, 1.15]);
  const luces = [];
  for (const lado of [1, -1]) {
    const x = (v) => (lado === 1 ? v : X(v));
    const curva = new THREE.CubicBezierCurve3(
      new THREE.Vector3(...P(x(219), 80), FRENTE + 0.03), new THREE.Vector3(...P(x(222), 114), FRENTE + 0.03),
      new THREE.Vector3(...P(x(226), 148), FRENTE + 0.03), new THREE.Vector3(...P(x(230), 176), FRENTE + 0.03));
    const tubo = zona("panel", new THREE.Mesh(new THREE.TubeGeometry(curva, 32, 0.016, 8), m.luz.clone()));
    mando.add(tubo);
    luces.push(tubo);
    despiece.push([tubo, 0.7, 1.15]);
  }

  // Cruceta: cuatro flechas separadas
  for (const a of [0, 90, 180, 270]) {
    const f = zona("cruceta", malla(extruir(flecha(138, 150, a), 0.05, 0.02, 2, 8), m.brillo));
    f.position.z = FRENTE + 0.02;
    mando.add(f);
    despiece.push([f, 0.55]);
  }

  // Botones de acción con su símbolo
  const B = [[502, 121, "triangulo"], [531, 150, "circulo"], [502, 179, "cruz"], [473, 150, "cuadrado"]];
  for (const [bx, by, sim] of B) {
    const b = zona("botones", malla(new THREE.CylinderGeometry(0.135, 0.14, 0.09, 40), m.brillo));
    b.rotation.x = Math.PI / 2;
    b.position.set(...P(bx, by), FRENTE + 0.07);
    mando.add(b);
    despiece.push([b, 0.6]);
    const s = simbolo(sim, m.simbolo.clone());
    s.position.set(...P(bx, by), FRENTE + 0.117);
    mando.add(zona("botones", s));
    despiece.push([s, 0.6]);
  }

  // Sticks: pozo, vástago y capuchón cóncavo de goma con su anillo
  for (const [z, sx] of [["izdo", 236], ["dcho", 404]]) {
    const g = new THREE.Group();
    const pozo = new THREE.Mesh(new THREE.TorusGeometry(0.33, 0.03, 12, 64), m.negro.clone());
    pozo.position.z = NUC - 0.03;
    g.add(pozo);
    const vastago = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.12, 0.22, 24), m.negro.clone());
    vastago.rotation.x = Math.PI / 2;
    vastago.position.z = NUC + 0.08;
    g.add(vastago);
    const perfil = [[0, 0.1], [0.08, 0.075], [0.18, 0.09], [0.235, 0.115], [0.255, 0.1], [0.26, 0.04], [0.25, 0], [0.0, 0]]
      .map(([r, h]) => new THREE.Vector2(r, h));
    const capuchon = new THREE.Mesh(new THREE.LatheGeometry(perfil, 64), m.goma.clone());
    capuchon.rotation.x = Math.PI / 2;
    capuchon.position.z = NUC + 0.18;
    g.add(capuchon);
    const anillo = new THREE.Mesh(new THREE.TorusGeometry(0.2, 0.012, 8, 64), m.negro.clone());
    anillo.position.z = NUC + 0.29;
    g.add(anillo);
    g.position.set(...P(sx, 222), 0);
    for (const h of g.children) zona(z, h);
    mando.add(g);
    despiece.push([g, 1.1, -0.95]);
  }

  // Create y Options, botón PS y silencio
  for (const [x, giro] of [[200, 0.28], [440, -0.28]]) {
    const c = malla(new THREE.CapsuleGeometry(0.035, 0.13, 6, 12), m.brillo);
    c.rotation.z = giro;
    c.position.set(...P(x, 96), FRENTE + 0.04);
    mando.add(c);
    despiece.push([c, 0.45]);
  }
  const ps = zona("ps", malla(new THREE.CylinderGeometry(0.1, 0.1, 0.05, 40), m.brillo));
  ps.rotation.x = Math.PI / 2;
  ps.position.set(...P(320, 216), NUC + 0.01);
  mando.add(ps);
  despiece.push([ps, 0.9, -0.95]);
  const silencio = malla(new THREE.CapsuleGeometry(0.035, 0.18, 6, 12), m.brillo);
  silencio.rotation.z = Math.PI / 2;
  silencio.position.set(...P(320, 243), NUC + 0.01);
  mando.add(zona("ps", silencio));
  despiece.push([silencio, 0.9, -0.95]);
  for (let i = 0; i < 5; i++) {
    const a = new THREE.Mesh(new THREE.CircleGeometry(0.012, 10), m.simbolo);
    a.position.set(...P(306 + i * 7, 194), NUC + 0.001);
    mando.add(a);
  }

  // Gatillos L2/R2 (detrás, inclinados hacia atrás) y botones L1/R1 en el borde de los hombros
  for (const [lado, x] of [["l", 145], ["r", 495]]) {
    // Perfil lateral del gatillo (u = hacia atrás, v = hacia arriba): una lengüeta curva
    const gat = new THREE.Shape();
    gat.moveTo(0, 0);
    gat.bezierCurveTo(0.05, 0.32, 0.3, 0.6, 0.66, 0.66);
    gat.bezierCurveTo(0.74, 0.67, 0.78, 0.6, 0.72, 0.55);
    gat.bezierCurveTo(0.42, 0.48, 0.2, 0.3, 0.14, 0.02);
    gat.lineTo(0, 0);
    const geo = extruir(gat, 0.62, 0.04, 3, 24);
    geo.translate(0, 0, -0.31);
    const g2 = zona(lado + "2", malla(geo, m.negro));
    g2.rotation.y = -Math.PI / 2;
    g2.position.set(P(x, 0)[0], 1.3, -0.34);
    mando.add(g2);
    despiece.push([g2, -0.7]);
    const b1 = zona("r1", malla(new THREE.CapsuleGeometry(0.075, 0.82, 8, 16), m.negro));
    b1.rotation.z = Math.PI / 2 + (lado === "l" ? 0.12 : -0.12);
    b1.scale.set(1, 1, 1.6);
    b1.position.set(P(x + (lado === "l" ? -6 : 6), 0)[0], 1.56, 0.12);
    mando.add(b1);
    despiece.push([b1, -0.4]);
  }

  // La placa p5k-ps5, entre la carcasa y el núcleo: solo se ve al desmontar
  const placa = new THREE.Group();
  const pcb = new THREE.Mesh(new THREE.BoxGeometry(2.48, 1.2, 0.06), new THREE.MeshPhysicalMaterial({ color: 0x1f5a3a, roughness: 0.45, clearcoat: 0.6 }));
  placa.add(pcb);
  const plata = new THREE.MeshStandardMaterial({ color: 0xc9ccd2, metalness: 1, roughness: 0.3 });
  const chipNegro = new THREE.MeshStandardMaterial({ color: 0x1a1a1c, roughness: 0.5 });
  const pieza = (w, h, d, mat, x, y) => { const p = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat); p.position.set(x, y, 0.03 + d / 2); placa.add(p); return p; };
  const esp = pieza(0.72, 0.72, 0.12, plata, -0.15, 0.12); // módulo ESP32-S3 (blindaje)
  const max = pieza(0.32, 0.32, 0.05, chipNegro, 0.62, 0.12); // MAX3421E
  const rotulo = (texto, obj, w, h, color) => {
    const c = document.createElement("canvas"); c.width = 512; c.height = Math.round(512 * h / w);
    const g = c.getContext("2d"); g.fillStyle = color; g.textAlign = "center"; g.textBaseline = "middle";
    g.font = `600 ${Math.round(c.height * 0.34)}px ui-monospace, Menlo, monospace`; g.fillText(texto, c.width / 2, c.height / 2);
    const tx = new THREE.CanvasTexture(c); tx.anisotropy = 4;
    const p = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ map: tx, transparent: true }));
    p.position.set(obj.position.x, obj.position.y, obj.position.z + obj.geometry.parameters.depth / 2 + 0.002);
    placa.add(p);
  };
  rotulo("ESP32-S3", esp, 0.62, 0.2, "#3a3d44");
  rotulo("MAX3421E", max, 0.3, 0.1, "#c9ccd2");
  pieza(0.3, 0.36, 0.13, plata, -1.1, 0.2);          // USB-C consola
  pieza(0.3, 0.36, 0.13, plata, 1.1, 0.2);           // USB-C mando
  pieza(0.24, 0.18, 0.04, chipNegro, -0.7, -0.3);    // regulador
  placa.position.set(0, 0.2, 0.15);
  placa.scale.setScalar(0.001);
  mando.add(placa);
  despiece.push([placa, 0.3]);

  // Centro visual algo más arriba que el geométrico. El mando flota. Centro visual algo más arriba que el geométrico.
  mando.position.y = -0.05;
  return { mando, zonas, despiece, luces, placa, materiales: m };
}

function simbolo(tipo, mat) {
  const g = new THREE.Group();
  const s = 0.062, t = 0.011;
  const borde = (pts) => {
    const forma = new THREE.Shape(pts.map(([x, y]) => new THREE.Vector2(x, y)));
    const hueco = new THREE.Path(pts.map(([x, y]) => new THREE.Vector2(x * (1 - (t * 2.6) / s), y * (1 - (t * 2.6) / s))).reverse());
    forma.holes.push(hueco);
    return new THREE.Mesh(new THREE.ShapeGeometry(forma), mat);
  };
  if (tipo === "circulo") g.add(new THREE.Mesh(new THREE.RingGeometry(s - t, s + t * 0.2, 40), mat));
  else if (tipo === "triangulo") g.add(borde([[0, s * 1.05], [s * 0.95, -s * 0.62], [-s * 0.95, -s * 0.62]]));
  else if (tipo === "cuadrado") g.add(borde([[-s * 0.8, -s * 0.8], [s * 0.8, -s * 0.8], [s * 0.8, s * 0.8], [-s * 0.8, s * 0.8]]));
  else if (tipo === "cruz") {
    for (const a of [Math.PI / 4, -Math.PI / 4]) {
      const b = new THREE.Mesh(new THREE.PlaneGeometry(s * 2.2, t * 2), mat);
      b.rotation.z = a;
      g.add(b);
    }
  }
  return g;
}
