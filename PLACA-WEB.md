# La placa sin ordenador: WiFi, app web y motor

La placa (ESP32-S3) hace lo mismo que la app de escritorio, sin ordenador:

- **Motor**: lee el DualSense real (por el MAX3421E), aplica el perfil (anti-recoil, ayuda al
  apuntado, turbo, macros, sticks, gatillos, botones…) y manda el resultado a la consola. Es el
  mismo código Rust que la app de escritorio (`escritorio/src-tauri/src/modelo.rs`,
  `procesador.rs`, `medidor.rs`, `monitor.rs`, `qr.rs`), compilado para el ESP32-S3 en
  `components/motor/`.
- **App web**: la misma página que sirve la app de Mac y la de escritorio (`app/Pagina.swift`),
  servida por la placa por WiFi, con las mismas rutas (`/perfil`, `/estado`, `/eventos`,
  `/medidor`, `/movil`, `POST /api`). La placa añade la pestaña **Placa** (capacidad `placa`).
- **WiFi con onboarding**: la placa se conecta a la red de casa; si no puede (no hay red
  configurada, o ha cambiado la contraseña del router), abre su propia red WiFi para configurarla.

## WiFi

| Situación | Qué hace la placa |
|---|---|
| Sin red de casa configurada | Abre su red propia (`p5k-ps5 XXXX`) |
| Red de casa configurada | Se conecta. Si en 20 s no lo consigue, abre también su red propia y sigue reintentando la de casa cada minuto (mientras nadie esté conectado a la red propia) |
| Se pierde la red de casa | Reintenta; si en 20 s no vuelve, abre su red propia |
| Conectada a la de casa | Cierra su red propia (salvo que se haya marcado «siempre encendida») |

- La red propia es **abierta** por defecto; se le puede poner contraseña (8 caracteres o más) desde
  la pestaña Placa.
- Al conectarte a la red propia, el móvil abre la página solo (portal cautivo: la placa contesta a
  todas las consultas DNS con su dirección, 192.168.4.1).
- En la red de casa la placa se anuncia como **http://puente.local** (mDNS); también vale su IP.
- Lo guardado (red de casa, red propia) va en la NVS, espacio `red`.

## Rescate

Si se olvida la contraseña de la red propia, o la placa está en una red de casa a la que no se puede
entrar (red de invitados, aislamiento de clientes…): **mantener BOOT 10 s** (la luz se pone blanca) o la
orden `wifi rescate` por el COM. La red propia queda **abierta y sin contraseña**, y encendida al menos
5 minutos aunque la placa esté en casa. `wifi olvidar` borra además la red de casa.

BOOT: pulsación corta = ✕; mantener 2 s (luz morada) y soltar = cambiar de modo; 10 s = rescate.

## Clave

Como en el Mac, todas las rutas (menos `/`, `/p`, `/portal` y `/icono.png`) piden la clave en `?k=`.
Tras 8 claves malas en un minuto, las claves malas reciben 429 durante un minuto (la buena entra siempre).

- **Entrando por la red propia de la placa**, la clave no hace falta: quien está en esa red ya ha
  pasado por su contraseña (si tiene). `GET /` desde la red propia redirige a `/p#k=CLAVE`, y la
  página se queda con la clave.
- **Entrando por la red de casa**, hace falta la clave. La pestaña Placa (y `/movil`) enseña la
  dirección con la clave y su código QR.
- `POST` exige además la cabecera `X-Puente: 1` (otra web no puede mandar esa cabecera sin permiso).

## Rutas nuevas (solo en la placa)

### `GET /wifi?k=`

```json
{
  "sta":  {"ssid": "Casa", "configurada": true, "conectada": true, "ip": "192.168.1.50", "rssi": -55,
           "conectando": false, "error": null},
  "ap":   {"ssid": "p5k-ps5 A1B2", "abierta": true, "activa": false, "siempre": false,
           "ip": "192.168.4.1", "clientes": 0},
  "redes": [{"ssid": "Casa", "rssi": -50, "segura": true}],
  "buscando": false,
  "direcciones": ["http://puente.local", "http://192.168.1.50"],
  "porRedPropia": false,
  "modo": "dualsense",
  "mandoReal": true,
  "firmware": "3a8f066"
}
```

- `redes`: el último escaneo, de más a menos señal, sin repetidas. `buscando` mientras escanea.
- `sta.conectando`: hay un intento en curso. `sta.error`: por qué falló el último («La contraseña no es
  correcta», «No se encuentra esa red», …) o `null`.
- `porRedPropia`: la petición llega por la red propia de la placa.
- `modo`: `consola` (mando de PS4 para el P5Mate), `dualsense` (relé directo a la PS5) o `mac`.
- `mandoReal`: hay un DualSense conectado al MAX3421E.

### `POST /wifi?k=` (con `X-Puente: 1`)

| Cuerpo | Qué hace |
|---|---|
| `{"accion":"conectar","ssid":"Casa","clave":"…"}` | Guarda la red de casa y se conecta |
| `{"accion":"olvidar"}` | Olvida la red de casa (se queda con la red propia) |
| `{"accion":"buscar"}` | Escanea redes (ver `buscando` en `GET /wifi`) |
| `{"accion":"ap","ssid":"…","clave":"","siempre":false}` | Nombre y contraseña de la red propia (`""` = abierta; si no, 8–63 caracteres). Se aplica en 2 s: quien esté conectado a la red propia se desconecta y tiene que volver a entrar |
| `{"accion":"modo","modo":"consola"}` | Cambia el modo de la placa (se reinicia) |
| `{"accion":"reiniciar"}` | Reinicia la placa |

Respuesta: `{"ok": true, "info": "texto opcional"}` o `{"ok": false, "error": "texto"}`.

### `POST /firmware?k=` (con `X-Puente: 1`)

El cuerpo es el `.bin` de la app (`build/puente_mando.bin`). La placa lo graba en la otra
partición OTA y se reinicia con él. Respuesta como la de `/wifi`.

- **No se puede desde la red propia si está abierta** (sin contraseña): cualquiera podría conectarse y
  grabar otro firmware. Desde la red propia con contraseña o desde la de casa, sí.
- **Vuelta atrás**: el firmware nuevo se confirma cuando lleva 30 s en marcha con la WiFi y el servidor
  web arrancados. Si se cuelga o se reinicia antes, la placa vuelve sola al anterior.

### `GET /movil?k=`

Igual que en el escritorio: `{"direcciones": [...], "qr": "<svg…>", "clientes": n, "puerto": 80,
"activo": true, "local": false}`. Las direcciones llevan la clave (`http://puente.local/#k=…`).

## Capacidades

`/perfil` devuelve `"capacidades": ["manual", "placa"]`. La pestaña Placa solo sale con `placa`.
