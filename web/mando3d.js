// El DualSense en 3D, construido con geometría a partir de las medidas calcadas de una foto de frente
// (dualsense-datos.js): la carcasa blanca, el núcleo negro que baja por dentro de las empuñaduras, el panel
// táctil entre las barras de luz, la cruceta de cuatro botones, los botones de acción con su aro, los sticks,
// el altavoz, el botón PS, el de silencio y los gatillos. La cara de los botones mira a +Z y el mando mide
// 6,4 unidades de ancho. Cada pieza lleva su zona («r2», «dcho», «botones»…) para poder iluminarla.
import * as THREE from "three";
import { DATOS } from "./dualsense-datos.js";
import { mergeVertices } from "./vendor/BufferGeometryUtils.js";

const S = DATOS.escala; // unidades por píxel de la foto
const V = (p) => new THREE.Vector2(p[0], p[1]);

// Contorno cerrado y suave: una spline que pasa por los puntos calcados
function formaDe(puntos) {
  const curva = new THREE.CatmullRomCurve3(puntos.map(([x, y]) => new THREE.Vector3(x, y, 0)), true, "centripetal");
  return new THREE.Shape(curva.getSpacedPoints(Math.max(120, puntos.length * 4)).map((p) => new THREE.Vector2(p.x, p.y)));
}

const extruir = (s, prof, bisel, seg = 4, curva = 24) => {
  const g = new THREE.ExtrudeGeometry(s, {
    depth: prof, bevelEnabled: bisel > 0, bevelThickness: bisel, bevelSize: bisel * 0.85, bevelSegments: seg, curveSegments: curva,
  });
  // Sin esto, cada cara del bisel se sombrea plana y el borde se ve en escalones
  const suave = mergeVertices(g.deleteAttribute("normal") && g.deleteAttribute("uv") ? g : g, 1e-4);
  suave.computeVertexNormals();
  return suave;
};

// Rectángulo redondeado centrado
function redondeado(w, h, r) {
  const s = new THREE.Shape();
  s.moveTo(-w / 2 + r, -h / 2);
  s.lineTo(w / 2 - r, -h / 2); s.quadraticCurveTo(w / 2, -h / 2, w / 2, -h / 2 + r);
  s.lineTo(w / 2, h / 2 - r); s.quadraticCurveTo(w / 2, h / 2, w / 2 - r, h / 2);
  s.lineTo(-w / 2 + r, h / 2); s.quadraticCurveTo(-w / 2, h / 2, -w / 2, h / 2 - r);
  s.lineTo(-w / 2, -h / 2 + r); s.quadraticCurveTo(-w / 2, -h / 2, -w / 2 + r, -h / 2);
  return s;
}

// Un botón de la cruceta: redondeado por fuera y en punta suave hacia el centro (apunta a -Y en local)
function flechaCruceta() {
  const w = 40 * S, l = 44 * S, r = 9 * S;
  const s = new THREE.Shape();
  s.moveTo(-w / 2 + r, l / 2);
  s.lineTo(w / 2 - r, l / 2); s.quadraticCurveTo(w / 2, l / 2, w / 2, l / 2 - r);
  s.lineTo(w / 2, -l / 2 + 12 * S); s.quadraticCurveTo(w / 2, -l / 2 + 4 * S, 6 * S, -l / 2);
  s.lineTo(-6 * S, -l / 2); s.quadraticCurveTo(-w / 2, -l / 2 + 4 * S, -w / 2, -l / 2 + 12 * S);
  s.lineTo(-w / 2, l / 2 - r); s.quadraticCurveTo(-w / 2, l / 2, -w / 2 + r, l / 2);
  return s;
}

// El panel táctil: por dentro de las barras de luz, arriba el borde del mando y abajo una curva suave
function panelTactil() {
  const izq = DATOS.barraIzq.map(([x, y]) => [x + 5 * S, y]);
  const der = DATOS.barraDer.map(([x, y]) => [x - 5 * S, y]);
  const [ai, bi] = [izq[0], izq[izq.length - 1]];
  const [ad, bd] = [der[0], der[der.length - 1]];
  const s = new THREE.Shape();
  s.moveTo(ai[0], ai[1] + 6 * S);
  for (const p of izq) s.lineTo(p[0], p[1]);
  const fondo = Math.min(bi[1], bd[1]) - 14 * S;
  s.quadraticCurveTo(bi[0] + 4 * S, fondo, bi[0] + 30 * S, fondo - 2 * S);
  s.quadraticCurveTo(0, fondo - 9 * S, bd[0] - 30 * S, fondo - 2 * S);
  s.quadraticCurveTo(bd[0] - 4 * S, fondo, bd[0], bd[1]);
  for (const p of [...der].reverse()) s.lineTo(p[0], p[1]);
  s.lineTo(ad[0], ad[1] + 6 * S);
  s.quadraticCurveTo(0, ad[1] + 12 * S, ai[0], ai[1] + 6 * S);
  return s;
}

export function materiales() {
  return {
    blanco: new THREE.MeshPhysicalMaterial({ color: 0xe3e6ee, roughness: 0.55, clearcoat: 0.25, clearcoatRoughness: 0.6 }),
    panel: new THREE.MeshPhysicalMaterial({ color: 0xd9dce5, roughness: 0.7, clearcoat: 0.1, clearcoatRoughness: 0.85 }),
    negro: new THREE.MeshPhysicalMaterial({ color: 0x08090c, roughness: 0.62, clearcoat: 0.3, clearcoatRoughness: 0.5, envMapIntensity: 0.35 }),
    brillo: new THREE.MeshPhysicalMaterial({ color: 0x0d0e12, roughness: 0.2, clearcoat: 1, clearcoatRoughness: 0.1 }),
    goma: new THREE.MeshStandardMaterial({ color: 0x101115, roughness: 0.9, envMapIntensity: 0.4 }),
    traslucido: new THREE.MeshPhysicalMaterial({ color: 0xc9cdd8, roughness: 0.16, clearcoat: 1, clearcoatRoughness: 0.08, transmission: 0.2, thickness: 0.2 }),
    simbolo: new THREE.MeshStandardMaterial({ color: 0x7c818d, roughness: 0.5 }),
    luz: new THREE.MeshStandardMaterial({ color: 0x0020ff, emissive: 0x1238ff, emissiveIntensity: 1.6, roughness: 0.3, toneMapped: false }),
  };
}

export function crearMando() {
  const m = materiales();
  const mando = new THREE.Group();
  const zonas = {};
  const despiece = []; // [objeto, desplazamiento en Z, desplazamiento en Y] al desmontarlo
  const zona = (z, obj) => { (zonas[z] ||= []).push(obj); obj.userData.zona = z; return obj; };
  const malla = (g, mat) => new THREE.Mesh(g, mat.clone());
  const P = DATOS.puntos;

  // Carcasa: el frente plano con un bisel generoso, y un lomo detrás algo más pequeño que redondea la espalda
  const carcasa = formaDe(DATOS.carcasa);
  // Un solo cuerpo con un bisel ancho y redondo: así el canto no se ve en capas
  const frente = malla(extruir(carcasa, 0.36, 0.2, 18, 96), m.blanco);
  frente.position.z = -0.24;
  mando.add(frente);
  despiece.push([frente, -0.9, 0]);
  const FRENTE = 0.32; // cara delantera de la carcasa

  // Núcleo negro, apenas por encima de la carcasa
  const nucleo = malla(extruir(formaDe(DATOS.negro), 0.012, 0.012, 2, 64), m.negro);
  nucleo.position.z = FRENTE - 0.004;
  mando.add(nucleo);
  despiece.push([nucleo, -0.3, 0]);
  const NUC = FRENTE + 0.02;

  // Panel táctil blanco mate, entre las barras de luz
  const panel = zona("panel", malla(extruir(panelTactil(), 0.02, 0.014, 3, 32), m.panel));
  panel.position.z = FRENTE + 0.004;
  mando.add(panel);
  despiece.push([panel, 0.7, 1.15]);
  const luces = [];
  for (const barra of [DATOS.barraIzq, DATOS.barraDer]) {
    const curva = new THREE.CatmullRomCurve3(barra.map(([x, y]) => new THREE.Vector3(x, y, FRENTE + 0.03)));
    const tubo = zona("panel", new THREE.Mesh(new THREE.TubeGeometry(curva, 48, 0.028, 8), m.luz.clone()));
    mando.add(tubo);
    luces.push(tubo);
    despiece.push([tubo, 0.7, 1.15]);
  }

  // Cruceta: cuatro botones redondeados alrededor de un centro, con su flechita
  const [cx, cy] = P.cruceta;
  for (let k = 0; k < 4; k++) {
    const a = (k * Math.PI) / 2;
    const b = zona("cruceta", malla(extruir(flechaCruceta(), 0.05, 0.03, 3, 12), m.traslucido));
    const d = 42 * S;
    b.rotation.z = a;
    b.position.set(cx - Math.sin(a) * d, cy + Math.cos(a) * d, FRENTE + 0.02);
    mando.add(b);
    despiece.push([b, 0.55, 0]);
    const f = new THREE.Shape([V([0, 5 * S]), V([4 * S, -2 * S]), V([-4 * S, -2 * S])]);
    const flecha = zona("cruceta", new THREE.Mesh(new THREE.ShapeGeometry(f), m.simbolo.clone()));
    flecha.rotation.z = a;
    flecha.position.set(cx - Math.sin(a) * (d + 4 * S), cy + Math.cos(a) * (d + 4 * S), FRENTE + 0.11);
    mando.add(flecha);
    despiece.push([flecha, 0.55, 0]);
  }

  // Botones de acción: traslúcidos, con el símbolo en gris
  const [bx, by] = P.botones;
  const sep = 61 * S;
  for (const [dx, dy, sim] of [[0, sep, "triangulo"], [sep, 0, "circulo"], [0, -sep, "cruz"], [-sep, 0, "cuadrado"]]) {
    const b = zona("botones", malla(new THREE.CylinderGeometry(25 * S, 26 * S, 0.1, 48), m.traslucido));
    b.rotation.x = Math.PI / 2;
    b.position.set(bx + dx, by + dy, FRENTE + 0.06);
    mando.add(b);
    despiece.push([b, 0.6, 0]);
    const s = zona("botones", simbolo(sim, m.simbolo.clone()));
    s.position.set(bx + dx, by + dy, FRENTE + 0.112);
    mando.add(s);
    despiece.push([s, 0.6, 0]);
  }

  // Create y Options: pastillas verticales
  for (const p of [P.create, P.options]) {
    const c = malla(extruir(redondeado(15 * S, 36 * S, 7 * S), 0.03, 0.015, 2, 8), m.blanco);
    c.position.set(p[0], p[1], FRENTE + 0.01);
    mando.add(c);
    despiece.push([c, 0.45, 0]);
  }

  // Sticks: pozo negro, capuchón de goma cóncavo con su borde estriado
  for (const [z, p] of [["izdo", P.stickIzq], ["dcho", P.stickDer]]) {
    const g = new THREE.Group();
    const pozo = new THREE.Mesh(new THREE.TorusGeometry(48 * S, 0.035, 12, 64), m.negro.clone());
    pozo.position.z = NUC - 0.03;
    g.add(pozo);
    const vastago = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.14, 0.2, 24), m.negro.clone());
    vastago.rotation.x = Math.PI / 2;
    vastago.position.z = NUC + 0.07;
    g.add(vastago);
    const R = 44 * S;
    const perfil = [[0, 0.085], [R * 0.4, 0.07], [R * 0.75, 0.085], [R * 0.92, 0.11], [R, 0.095], [R * 1.01, 0.03], [R * 0.96, 0], [0, 0]]
      .map(([r, h]) => new THREE.Vector2(r, h));
    const capuchon = new THREE.Mesh(new THREE.LatheGeometry(perfil, 72), m.goma.clone());
    capuchon.rotation.x = Math.PI / 2;
    capuchon.position.z = NUC + 0.16;
    g.add(capuchon);
    const borde = new THREE.Mesh(new THREE.TorusGeometry(R * 0.93, 0.014, 8, 72), m.negro.clone());
    borde.position.z = NUC + 0.27;
    g.add(borde);
    g.position.set(p[0], p[1], 0);
    for (const h of g.children) zona(z, h);
    mando.add(g);
    despiece.push([g, 1.1, -0.95]);
  }

  // Altavoz (2 × 5 agujeros), botón PS y botón de silencio
  const [ax, ay] = P.altavoz;
  for (let f = 0; f < 2; f++) for (let c = 0; c < 5; c++) {
    const a = new THREE.Mesh(new THREE.CircleGeometry(4.2 * S, 12), new THREE.MeshBasicMaterial({ color: 0x050506 }));
    a.position.set(ax + (c - 2) * 14 * S + (f ? 0 : 0), ay + (f ? -7 : 7) * S, NUC + 0.001);
    mando.add(a);
  }
  const ps = zona("ps", new THREE.Mesh(new THREE.PlaneGeometry(56 * S, 34 * S), new THREE.MeshPhysicalMaterial({ map: logoPS(), transparent: true, roughness: 0.25, clearcoat: 1 })));
  ps.position.set(P.ps[0], P.ps[1], NUC + 0.004);
  mando.add(ps);
  despiece.push([ps, 0.9, -0.95]);
  const silencio = zona("ps", malla(extruir(redondeado(40 * S, 10 * S, 5 * S), 0.015, 0.01, 2, 8), m.brillo));
  silencio.position.set(P.silencio[0], P.silencio[1], NUC);
  mando.add(silencio);
  despiece.push([silencio, 0.9, -0.95]);

  // Gatillos L2/R2 (con L1/R1 delante): la silueta de la foto, con profundidad hacia atrás
  DATOS.gatillos.forEach((contorno, i) => {
    const g = zona(i === 0 ? "l2" : "r2", malla(extruir(formaDe(contorno), 0.42, 0.06, 4, 24), m.negro));
    g.position.z = -0.34;
    mando.add(g);
    despiece.push([g, -0.6, 0.25]);
  });

  // La placa p5k-ps5, entre la carcasa y el núcleo: solo se ve al desmontar
  const placa = new THREE.Group();
  placa.add(new THREE.Mesh(new THREE.BoxGeometry(2.48, 1.2, 0.06), new THREE.MeshPhysicalMaterial({ color: 0x1f5a3a, roughness: 0.45, clearcoat: 0.6 })));
  const plata = new THREE.MeshStandardMaterial({ color: 0xc9ccd2, metalness: 1, roughness: 0.3 });
  const chipNegro = new THREE.MeshStandardMaterial({ color: 0x1a1a1c, roughness: 0.5 });
  const pieza = (w, h, d, mat, x, y) => { const p = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat); p.position.set(x, y, 0.03 + d / 2); placa.add(p); return p; };
  const esp = pieza(0.72, 0.72, 0.12, plata, -0.15, 0.12);
  const max = pieza(0.36, 0.36, 0.05, chipNegro, 0.62, 0.12);
  pieza(0.3, 0.36, 0.13, plata, -1.1, 0.2);
  pieza(0.3, 0.36, 0.13, plata, 1.1, 0.2);
  pieza(0.24, 0.18, 0.04, chipNegro, -0.7, -0.3);
  rotulo(placa, "ESP32-S3", esp, 0.62, 0.2, "#3a3d44");
  rotulo(placa, "MAX3421E", max, 0.34, 0.12, "#d6d9df");
  placa.position.set(0, 0.2, 0.15);
  placa.scale.setScalar(0.001);
  mando.add(placa);
  despiece.push([placa, 0.3, 0]);

  return { mando, zonas, despiece, luces, placa, materiales: m };
}

function rotulo(placa, texto, obj, w, h, color) {
  const c = document.createElement("canvas"); c.width = 512; c.height = Math.round((512 * h) / w);
  const g = c.getContext("2d"); g.fillStyle = color; g.textAlign = "center"; g.textBaseline = "middle";
  g.font = `600 ${Math.round(c.height * 0.38)}px ui-monospace, Menlo, monospace`; g.fillText(texto, c.width / 2, c.height / 2);
  const tx = new THREE.CanvasTexture(c); tx.anisotropy = 4;
  const p = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ map: tx, transparent: true }));
  p.position.set(obj.position.x, obj.position.y, obj.position.z + obj.geometry.parameters.depth / 2 + 0.002);
  placa.add(p);
}

// El logo del botón PS, dibujado (la «P» en pie y la «S» tumbada), negro brillante sobre transparente
function logoPS() {
  const c = document.createElement("canvas"); c.width = 330; c.height = 200;
  const g = c.getContext("2d");
  g.fillStyle = "#07080a";
  g.beginPath(); // la P
  g.moveTo(132, 8); g.lineTo(132, 168); g.lineTo(170, 184); g.lineTo(170, 52);
  g.bezierCurveTo(170, 36, 200, 36, 200, 56); g.lineTo(200, 104);
  g.bezierCurveTo(232, 116, 262, 100, 262, 64); g.bezierCurveTo(262, 26, 236, 14, 196, 6);
  g.bezierCurveTo(176, 2, 150, -2, 132, 8); g.closePath(); g.fill();
  g.beginPath(); // la S tumbada, en dos trazos
  g.moveTo(20, 150); g.bezierCurveTo(-6, 166, 20, 182, 70, 190); g.lineTo(122, 196); g.lineTo(122, 172);
  g.lineTo(80, 162); g.bezierCurveTo(56, 156, 58, 146, 80, 140); g.lineTo(122, 126); g.lineTo(122, 102);
  g.lineTo(62, 122); g.bezierCurveTo(40, 130, 30, 140, 20, 150); g.closePath(); g.fill();
  g.beginPath();
  g.moveTo(180, 150); g.lineTo(180, 174); g.lineTo(256, 148); g.bezierCurveTo(290, 136, 278, 120, 246, 120);
  g.bezierCurveTo(226, 120, 204, 126, 180, 134); g.lineTo(180, 156); g.lineTo(240, 138); g.bezierCurveTo(254, 134, 258, 140, 244, 144); g.closePath(); g.fill();
  const t = new THREE.CanvasTexture(c); t.anisotropy = 4; t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function simbolo(tipo, mat) {
  const g = new THREE.Group();
  const s = 13 * S, t = 1.6 * S;
  const borde = (pts) => {
    const forma = new THREE.Shape(pts.map(([x, y]) => new THREE.Vector2(x, y)));
    const k = 1 - (t * 2.4) / s;
    forma.holes.push(new THREE.Path(pts.map(([x, y]) => new THREE.Vector2(x * k, y * k)).reverse()));
    return new THREE.Mesh(new THREE.ShapeGeometry(forma), mat);
  };
  if (tipo === "circulo") g.add(new THREE.Mesh(new THREE.RingGeometry(s - t, s + t * 0.3, 48), mat));
  else if (tipo === "triangulo") g.add(borde([[0, s * 1.08], [s * 0.98, -s * 0.66], [-s * 0.98, -s * 0.66]]));
  else if (tipo === "cuadrado") g.add(borde([[-s * 0.82, -s * 0.82], [s * 0.82, -s * 0.82], [s * 0.82, s * 0.82], [-s * 0.82, s * 0.82]]));
  else if (tipo === "cruz") for (const a of [Math.PI / 4, -Math.PI / 4]) {
    const b = new THREE.Mesh(new THREE.PlaneGeometry(s * 2.3, t * 1.8), mat);
    b.rotation.z = a;
    g.add(b);
  }
  return g;
}
