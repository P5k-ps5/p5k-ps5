# Caja impresa en 3D

Para el ESP32-S3 (YD-ESP32-S3 N16R8, 57 × 27,7 mm, filas de pines a 1") y el MAX3421E (DuinoFUN USB mini). La genera `caja.py`
(paramétrica: todas las medidas están arriba del archivo). Tres variantes:

| Variante | Medidas (largo × ancho × alto) | Cables |
|---|---|---|
| `conectable/` | 68 × 32 × 30 mm | Soldados por arriba del MAX3421E; hembras Dupont enchufadas a los pines del ESP32 (se puede desmontar) |
| `compacta/` | 68 × 32 × 21,4 mm | Soldados por arriba del MAX3421E y directamente a los pines del ESP32 |
| `plana/` | 68 × 32 × 18 mm | Sin los plásticos de los pines y con los pines cortados a ras en las dos placas; cables soldados a los muñones. **USB-C en un extremo y USB-A en el contrario** |

En la conectable y la compacta, **los pines de debajo del MAX3421E se cortan a ras** (con alicates de corte)
después de soldar los cables por arriba.

En la **plana**, los plásticos de las tiras de pines (el amarillo del ESP32 y el negro del MAX) salen tirando con
unos alicates sin desoldar nada. Luego los pines se cortan a ras de la placa (dejando como mucho 1 mm) y los
cables se sueldan a esos muñones: en el ESP32 por debajo, en el MAX por arriba. El MAX va tumbado en el suelo
y el ESP32 justo encima de su USB-A, que queda debajo de la antena: antes de imprimir, comprueba con la orden
`wifi` que la señal no baja mucho con el USB-A pegado bajo la antena.

Cada carpeta trae `caja-base.stl`, `caja-tapa.stl`, `prueba-puertos.stl`, `vistas.png` y `visor.html` (el montaje
en 3D: se abre en el navegador, se gira con el ratón, y deja abrir la tapa, separar las piezas y cortar la caja).

## Cómo va por dentro (conectable y compacta)

- **ESP32** arriba, boca arriba. Por delante lo sujetan sus dos USB-C, que entran justos en sus agujeros; por
  detrás apoya en un pilar y en un poste bajo la antena (plástico, no molesta a la WiFi). Al cerrar, la tapa
  lo aprieta con dos topes (sobre el módulo y sobre los USB-C). Ni tornillos ni pegamento.
- **MAX3421E** debajo, tumbado entre las dos filas de pines del ESP32. Por delante lo sujeta su USB-A, que
  entra justo en su agujero; por detrás apoya en un tope y una pinza flexible lo engancha por encima (clic).
- **Conectores**, todos en la misma cara: los dos USB-C del ESP32 arriba (consola y COM) y el USB-A del mando
  abajo. La antena queda en el otro extremo, sin nada encima ni debajo.
- **Tapa** a presión. **BOOT**: lengüeta flexible con un pulsador por debajo. **RST**: agujero pequeño (se pulsa
  con un clip, para no reiniciar sin querer). **LED**: ventanita.

En la **plana** cambia esto: los USB-C salen por una cara y el USB-A por la contraria; el ESP32 apoya en un pilar
entre los USB-C y el MAX y en dos postes de plástico bajo los bordes de la antena, a los lados del USB-A, y la pestaña de
la tapa solo va por los laterales (el techo queda casi pegado a los componentes).

## Antes de imprimir

1. **Comprueba con una regla** las medidas marcadas `COMPROBAR` en `caja.py` (ancho de la placa del ESP32,
   separación de los USB-C y lo que sobresalen, y el tamaño del USB-A). Salen de fotos de las placas reales,
   con el paso de los pines como regla: ±0,5 mm.
2. **Imprime primero `prueba-puertos.stl`** (la cara de los conectores y 12 mm de caja, unos 20 min; en la plana
   son dos piezas, una por cara): mete el ESP32 y el MAX3421E y mira que los tres conectores entran justos. Si algo no cuadra, se cambia la medida en
   `caja.py` y se vuelve a generar: `python3 caja.py`.

## Imprimir

- PLA o PETG, capa de 0,2 mm, 3 perímetros, relleno 20 %. Sin soportes.
- La base, con la abertura hacia arriba. La tapa sale ya boca abajo (la cara de fuera sobre la cama).
- Si la lengüeta de BOOT queda dura, lija un poco la zona fina de la bisagra.

## Montar

1. El MAX3421E: mete el USB-A en su agujero desde dentro y baja la parte de atrás hasta que la pinza haga clic.
2. Conecta los cables al ESP32 (o suéldalos, en la compacta).
3. El ESP32: mete los dos USB-C en sus agujeros y baja la parte de atrás hasta que apoye.
4. Cierra la tapa.

## Caja de la placa p5k-ps5 (`placa/`)

Para la placa propia de `../placa/` (62 × 30 mm, montada por JLCPCB). La genera `placa_caja.py`:

```bash
python3 placa_caja.py --vistas   # placa/caja-base.stl, placa/caja-tapa.stl, placa/datos.json, placa/vistas.png
```

- Por fuera, 66,2 × 40,7 × 9,5 mm; unos 13 g de PETG o PLA. Capa de 0,2 mm, 3 perímetros, relleno 20 %.
- Sin soportes: la base boca arriba y la tapa boca abajo (el STL de la tapa ya viene así).
- Los dos USB-C a los lados (CONSOLA a la izquierda, MANDO a la derecha), con un rebaje por fuera para que el
  cable entre hasta el fondo. Sobre la antena, que sobresale 6,5 mm por arriba de la placa, solo hay plástico.
- La tapa entra a presión con un labio, sujeta la placa con cuatro pivotes y lleva dos botones flexibles sobre
  RST y BOOT, un agujero para el LED y, grabados, el nombre, los puertos y el QR de la web (el de la placa queda
  tapado). Para que el móvil lea el QR, pásale un rotulador negro.
- Sin imprimir ni probar todavía, como la placa: si el cable USB-C no entra hasta el fondo, sube el rebaje
  (`USB_REBAJE`) o baja la pared (`PARED`).

La web (sección «Descargas») enseña las dos cajas en 3D y deja descargar sus STL y los archivos de JLCPCB.
