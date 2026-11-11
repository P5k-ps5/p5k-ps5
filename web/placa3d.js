// La placa p5k-ps5 en 3D, sencilla: el PCB verde con el módulo ESP32-S3, el MAX3421E, los dos USB-C y el
// regulador, con los dos chips rotulados. Se ve dentro del mando en la parada «Por dentro».
import * as THREE from "three";

export function crearPlaca() {
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
  return placa;
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
