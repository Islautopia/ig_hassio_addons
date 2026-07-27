# Coordinación HA (add-on + card) ↔ firmware/nube (IG Doorbell)

Registro vivo de lo que la **integración de Home Assistant** (`ig_hassio_addons` +
`islautopia-intercom-card`) necesita saber o necesita que implemente el **firmware**
(`../IG_Doorbell`) / la **nube-VPS** (`hetzner-doorbell`, relay + coturn). La fuente de verdad de
la interfaz sigue siendo `API_CONTRACT.md`; aquí solo se rastrean las **preguntas abiertas y
acuerdos** hasta que se reflejen en el contrato. Mismo formato que
`IG_Doorbell_App/COORDINATION.md` (equipo Android/iOS).

**Leyenda de estado:** 🔴 abierta · 🟡 respondida, pendiente de implementar · 🟢 cerrada
(implementada/verificada y, si aplica, ya en `API_CONTRACT.md`).

---

## 🟢 Q1 — Nombre de dominio de la integración y ubicación en el repo (resuelto 2026-07-09)

> Respuesta del líder: repo nuevo dedicado, separado de `ig_hassio_addons` — integración HACS y
> add-on Supervisor son mecanismos de distribución/ciclos de release distintos, no mezclar con el
> addon (usuarios reales, tags `rc0.1`..`rc1.1`). Creado
> **[`islautopia-doorbell-integration`](https://github.com/Islautopia/islautopia-doorbell-integration)**
> (`C:\Proyectos_espressif\islautopia-doorbell-integration`), dominio HA `islautopia_doorbell`.
> Implementación inicial ya escrita: `custom_components/islautopia_doorbell/` (manifest, config
> flow con Zeroconf + entrada manual, despachador MQTT, puente WebSocket para la card).

## 🟢 Q2 — Confirmar alcance: sin sesión administrativa persistente (resuelto 2026-07-09)

> Respuesta del líder: confirmado, diseño correcto tal cual — no hace falta polling ni persistir
> contraseña de admin, el MQTT discovery del firmware ya cubre el estado que HA necesita.
> Implementado así en `custom_components/islautopia_doorbell/api.py`/`config_flow.py`.

## 🟡 Q3 — Topics MQTT planos sin `device_id` (hallazgo, deuda de backlog en firmware)

> Respuesta del líder: hallazgo real, bien identificado, no bloquea ni toca a este lado —
> anotado como deuda de backlog en firmware (solo importa con 2+ doorbells en la misma
> instalación de HA). No se ha tocado nada de nuestro diseño por esto.

## 🟢 Q4 — Futuro del add-on Docker (`islautopia_intercom`) (resuelto 2026-07-09 — más lejos de lo propuesto)

> Respuesta del líder: el usuario pidió ir más lejos que la propuesta original — no solo
> re-etiquetar, sino **deprecación activa y visible**: banner de aviso prominente al principio de
> `README.md` y `DOCS.md` del add-on (no una nota al pie), dejando claro que la vía recomendada
> para hardware Islautopia es `islautopia-doorbell-integration`, y que el add-on queda como modo
> de compatibilidad RTSP/go2rtc genérico para intercomunicadores de terceros. **Sin romper nada**
> funcionalmente — usuarios reales instalados. **Hecho**: banners añadidos en
> `islautopia_intercom/README.md`, `islautopia_intercom/DOCS.md`, y el `README.md` raíz del repo
> (listado de add-ons). Duda de DuckDNS: confirmada como recuerdo del propio usuario, sin nada
> real que migrar — cerrada sin más acción.

## 🟢 Q5 — `label` de `pair_app` para la integración de HA (resuelto 2026-07-09)

> Respuesta del líder: usar `"Home Assistant"` como label base. Implementado como
> `DEFAULT_PAIR_LABEL` en `custom_components/islautopia_doorbell/const.py`.

## 🟢 Q6 — Formato/estabilidad de `_igdoorbell._tcp.local.` para el `zeroconf` de HA (resuelto 2026-07-09)

> Respuesta del líder: el nombre de INSTANCIA mDNS puede cambiar (se deriva de `device_name`,
> editable en cualquier momento) — no usarlo como clave de matching. Usar el TXT record
> `device_id` (estable, derivado de la MAC). **Ya implementado así** en
> `config_flow.py::async_step_zeroconf()` (match por `discovery_info.properties["device_id"]`,
> nunca por el nombre de instancia) y documentado explícitamente en `const.py`/`discovery.py`.

---

## 🟡 Q7 — Nuevo hallazgo al implementar la card: HTTPS del doorbell por hostname, nunca por IP

Al escribir el transporte nativo de la card (`islautopia-intercom-card.js`) surgió una restricción
que no estaba explícita en el diseño original y que vale la pena que conste, aunque no bloquea
nada de nuestro lado:

- El certificado Let's Encrypt real del doorbell (`API_CONTRACT.md` §2) está emitido para el
  **hostname** `<device_id>.doorbell.islautopia.com`, no para ninguna IP — conectar por IP cruda
  (aunque sea la misma IP a la que resuelve ese hostname) haría que el navegador rechazara el
  certificado por no coincidir el nombre. Consecuencia: la card **siempre** conecta al doorbell
  por el hostname público (nunca por la IP resuelta vía mDNS), incluso en LAN — esto además evita
  el problema de "mixed content" si el propio dashboard de HA se sirve por HTTPS (un `fetch()`
  contra `http://<ip-local>` desde una página `https://` está bloqueado por el navegador).
- Consecuencia práctica: el `local_host` resuelto por mDNS server-side en
  `custom_components/islautopia_doorbell/discovery.py` **no lo usa directamente la card** para
  construir la URL de señalización — la card solo necesita el `device_id` (para construir el
  hostname) y no la IP. Dejamos ese campo en `get_connection_info` de todas formas (informativo,
  y útil si en el futuro hace falta un fallback HTTP puro en LANs sin salida a internet), pero no
  es la pieza crítica que pensábamos al diseñar `websocket_api.py`.
- Nota aparte, no una pregunta: esto también confirma por qué el rol de "HTTPS genérico para toda
  la instancia HA" del add-on legacy (Q4) sigue siendo un problema real y distinto — el
  certificado del doorbell solo asegura la conexión AL doorbell, nunca el origen del propio
  dashboard de HA. Si la instancia de HA de un usuario se sirve en HTTP plano local, ni esta card
  ni la nueva integración pueden arreglarle el acceso al micrófono — sigue haciendo falta HTTPS en
  el origen de HA en sí (Nabu Casa, el add-on legacy, u otro proxy propio).

No es una pregunta que necesite respuesta — se deja documentada por si es útil para la app/otros
consumidores del contrato que enfrenten la misma restricción de hostname-vs-IP con el certificado
del doorbell.

---

## ⚪ Confirmaciones ya resueltas (no repreguntar)

- **Payload de `videoportero/door/action`**: `{"action":"open","entity_id":"<ha_e>"}`, JSON desde
  2026-07-09 (antes texto plano `"OPEN"`). Verificado leyendo `main/hardtask.c::open_door()`
  directamente. Contrato §4.
- **Autodiscovery se re-publica en cada evento real** (no solo al conectar) — no afecta a nuestro
  despachador MQTT (solo nos importa `videoportero/door/action`, no el discovery), pero sí explica
  por qué las entidades nativas del firmware (modo/timbre/puerta/persona) reaparecen solas si el
  usuario las borra en HA.
- **`app_turn_credentials` es la vía correcta para TURN del lado card/app** — no reinventar nada
  aquí, contrato §3.1-bis, ya verificado en producción por el lado firmware.

---

## 🟢 Q9 — `/webrtc/signal`/`/webrtc/signal/post` locales ya exigen credencial (2026-07-09) — aplicado, sin fricción

El líder cerró un hueco de seguridad real: la señalización LOCAL (la que usa nuestro modo
`native`) ya no acepta conexiones sin credencial — acepta cookie de sesión de dashboard
(irrelevante para nosotros) O `?token=<credencial de pair_app>` como query param (`EventSource`
no admite cabeceras propias, de ahí el query string en vez de `Authorization`), validado
100% local/offline en el propio dispositivo. Es la MISMA credencial de 64 hex que ya
obteníamos de `pair_app` y ya usábamos para el WS remoto — no hace falta ningún secreto nuevo,
ni rompe la decisión Q2 (sin sesión de dashboard persistida).

**Aplicado sin fricción real** en `islautopia-intercom-card/dist/islautopia-intercom-card.js`:
`tryLocalSignaling()` añade `?token=<credencial>` a la URL del `EventSource`
(`/webrtc/signal?token=...`), y `sendNativeSignal()` añade el mismo `?token=` al `fetch` del
POST (`/webrtc/signal/post?token=...`) cuando el transporte activo es el local. La credencial ya
estaba disponible en `this._connInfo.credential` desde `get_connection_info` (websocket_api.py) —
no hizo falta ningún cambio en el backend de la integración, solo en la card. Sintaxis
re-verificada con `node --check`. Sin probar en real todavía (misma limitación de siempre, sin
instancia de HA disponible) pero el cambio es mecánico y de bajo riesgo.

---

## 🟢 Q8 — Add-on nuevo `islautopia_ha_https`, contrato del VPS `/ha_instance/*` ya verificado en real (2026-07-09)

Pieza nueva pedida por el líder tras la Q7: `getUserMedia()` exige *secure context* del origen
que sirve la card (Home Assistant), no del doorbell — el certificado real del propio doorbell no
resuelve esto. Construido `islautopia_ha_https/` (add-on Docker/Supervisor nuevo, separado del
legacy) — obtiene/renueva un certificado real para `<ha_instance_id>.ha.doorbell.islautopia.com`
(mismo mecanismo DNS-01/Route53 que el doorbell) y hace proxy inverso transparente de TODO
`homeassistant:8123` en el puerto 8443. Detalle completo del diseño e implementación en
`ARCHITECTURE.md` §6-bis.

> El líder confirmó que el contrato del VPS (`POST /ha_instance/register`,
> `POST /ha_instance/<id>/report_ip`, `GET /ha_instance/<id>/cert`) está **desplegado y
> verificado en real** contra `relay.doorbell.islautopia.com` (mismo host que ya usa el propio
> doorbell para `/register`) — register/report_ip/cert probados de extremo a extremo, incluida
> una emisión real de certificado Let's Encrypt de prueba, entrada de prueba ya limpiada de
> `ha_instances.json`. `run.sh` ya usa ese host como `API_BASE`, sin marcarlo como asunción
> pendiente de confirmar — ya está confirmado.

No queda ninguna pregunta abierta de este lado sobre el contrato en sí. Lo único pendiente es
probar el add-on completo contra una instancia real de Home Assistant (el usuario ha autorizado
acceso completo — URL, token de larga duración, SSH/Samba — para hacerlo; credenciales
pendientes de entrega por la sesión líder a fecha de esta entrada).

---

## 🟢 Q10 — Verificación end-to-end en HA real: add-on + recurso Lovelace (2026-07-09) — CERRADA, sin bugs encontrados

**Ejecutado por la sesión líder** (con la cuenta dedicada `claude`/`kakatua96!` que el usuario
creó explícitamente para el equipo, vía Playwright headless contra `http://192.168.42.138:8123`,
HA 2026.6.4) tras copiar los tres artefactos por SMB. Esta sesión (HA integration) revisó el log
real línea por línea contra `run.sh` — coincide exactamente, sin discrepancias:

```
Starting Islautopia HTTPS for Home Assistant...
Sin identidad propia todavia - registrando esta instancia de Home Assistant...
Nueva identidad registrada: d01d1aafaaa8fcc0
IP local: 192.168.42.138 (antes: ninguna conocida) - actualizando registro DNS...
Solicitando certificado para d01d1aafaaa8fcc0.ha.doorbell.islautopia.com...
Certificado actualizado (hash 62647e5f22507fdb0e328c08edb2aea3aa9b77bf9d933c5a90547ba843448a1f).
==================================================================
 Islautopia HTTPS for Home Assistant esta funcionando
==================================================================
 Accede a Home Assistant de forma segura (certificado real) en:
    https://d01d1aafaaa8fcc0.ha.doorbell.islautopia.com:8443
```

Caddy confirma servidor activo en `:8443` (h1/h2/h3, limpieza de storage TLS OK). "Iniciar en el
arranque" quedó activado por defecto tras instalar (coherente con `"boot": "auto"` en
`config.json`). **Primer despliegue real de `islautopia_ha_https` con éxito completo, sin ningún
ajuste de código necesario.**

Recurso Lovelace `/local/islautopia-intercom-card.js` (tipo "Módulo JavaScript") registrado con
éxito, coexistiendo sin conflicto con el recurso antiguo instalado vía HACS
(`/hacsfiles/islautopia-intercom-card/...`, dejado intacto a propósito — no se pidió deprecarlo
todavía). Fichero real confirmado en `config/www/islautopia-intercom-card.js` (40351 bytes).

**Nota de terminología de UI, no de código**: en HA 2026.6.4 la sección se llama "Aplicaciones",
no "Complementos" — el resto del flujo de instalación es idéntico. Vale la pena tenerlo en cuenta
si el nombre de la sección varía entre versiones de HA al escribir instrucciones para usuarios.

**Pendiente, exclusivo del usuario** (no bloqueado, solo a la espera de que vuelva): paso 4
(emparejar la integración `islautopia_doorbell` con el email/contraseña de administrador del
propio doorbell físico) y paso 6 (añadir la card a un dashboard, depende del 4 para que el
`ha-selector` tenga algo que listar).

---

## 🟢 Q11 — Bug real encontrado tras el paso 4: dispositivo sin entidades (2026-07-09) — CORREGIDO

El usuario completó el paso 4 (emparejamiento real) y reportó: "Integración instalada
aparentemente bien. entrando en el dispositivo de la integración no aparece ninguna entidad."
Confirmado por el líder vía Playwright: 1 dispositivo creado ("IG Doorbell v2"), pero "Este
dispositivo no tiene entidades" / "No se encontró actividad", **sin ningún error en Registros**
filtrando por "islautopia" — HA considera el setup exitoso, simplemente no hay entidades.

**Causa raíz confirmada leyendo el firmware real** (`main/networktask.c`, línea 121): la MQTT
discovery del propio doorbell registra su `device` con
`"dev":{"ids":["ig_doorbell_<dev_id>"],...}` — eso crea, en el device registry de HA, un
dispositivo con identifier `("mqtt", "ig_doorbell_<device_id>")`, propiedad de la integración
`mqtt`, **completamente distinto** del que nuestra integración registraba
(`("islautopia_doorbell", "<device_id>")`, sin `ig_doorbell_` de prefijo y con dominio distinto).
Resultado: dos dispositivos separados en HA — el nuestro (vacío, el que ve el usuario al entrar
desde "Islautopia Doorbell") y uno aparte, "IG-Doorbell", con las entidades reales
(modo/timbre/puerta/persona/abrir), sin ninguna relación visible entre ambos.

**Corregido** en `islautopia-doorbell-integration/custom_components/islautopia_doorbell/__init__.py`:
`device_registry.async_get_or_create()` ahora registra **ambos** identifiers en el mismo
dispositivo (`{(DOMAIN, device_id), ("mqtt", f"ig_doorbell_{device_id}")}`) — HA fusiona
automáticamente ambos dispositivos en uno solo en cuanto detecta el identifier compartido
(mecanismo estándar del device registry, no un hack), sin importar el orden en que cada
integración lo registre. El identifier propio se mantiene también (necesario para que el
`ha-selector` del editor de la card siga encontrando el dispositivo, ver `websocket_api.py`).

**Importante, no confundir con otro bug**: esta corrección hace que el dispositivo SÍ muestre las
entidades **si la MQTT discovery del propio doorbell ya está funcionando** (broker configurado en
el dispositivo, `door_mode` acorde). Si el doorbell de pruebas no tiene el broker MQTT
configurado todavía, seguirá sin entidades tras este fix — eso ya no seria un bug de la
integración, sería un paso de configuración pendiente en el propio doorbell (Red y MQTT en su
dashboard/app, ver `API_CONTRACT.md` §1.2-bis).

**Bug adicional, no relacionado, encontrado en la misma sesión de pruebas**: con el recurso
Lovelace antiguo de HACS y el nuevo `/local/...` cargados a la vez en el navegador (iPad del
usuario), colisionan al registrar el mismo custom element (`Failed to execute 'define' on
'CustomElementRegistry'...`) — no solo ensucia la consola, sino que dependiendo del orden de
carga podría dejar activa la copia ANTIGUA de HACS en vez de la que se está probando.
**Corregido** con guardas de idempotencia en `islautopia-intercom-card.js` (`customElements.get(...)`
antes de `define`, con `console.warn` explícito de cuál copia gana) — mitiga el crash, pero la
solución real durante esta fase de pruebas es mantener activo un solo recurso a la vez (ver
mensaje de despliegue).

Sintaxis re-verificada en ambos repos (`python -m py_compile`, `node --check`). Pendiente:
redesplegar los ficheros corregidos y verificar en real que el dispositivo fusionado ya muestra
las entidades.

---

## 🟡 Q12 — URL de acceso resaltada en el log de `islautopia_ha_https` (2026-07-09, prioridad baja)

Petición del usuario: resaltar con color la URL de acceso local en el log de arranque del add-on,
como link clicable si es posible, y que salga DOS veces (al principio Y al final, no solo al
final como hasta ahora), junto a las instrucciones de dónde configurar la URL de red en HA.

**Implementado** en `islautopia_ha_https/run.sh`: nueva función `print_highlighted_url()` — color
ANSI (`ESC[1;36m`, confirmado que se renderiza bien en el visor del Supervisor) + envoltorio
OSC 8 (`ESC]8;;URL ST TEXTO ESC]8;;ST`) para intentar que sea clicable donde el visor lo soporte.
Aparece ahora al principio del log (justo tras conocer el hostname, antes de que el add-on
termine de arrancar del todo) y al final (banner de "esta funcionando", como antes) — ambas
instancias incluyen la instrucción "Ajustes → Sistema → Red → URL de Home Assistant".

**Nota real de implementación, no solo de diseño**: la primera versión de
`print_highlighted_url()` (construyendo las secuencias de escape como texto literal `\033...`
para que `printf` las interpretara en tiempo de ejecución) tenía un bug real — verificado con
`cat -A`, algunas secuencias `\033` consecutivas con un `\\` de por medio (el terminador ST de
OSC 8) no se expandían todas, dejando texto literal `\033[0m` sin convertir en el reset final.
Corregido construyendo los bytes ESC con comillas ANSI-C (`$'\033'`, resueltas por el propio
shell al analizar el script) en vez de depender del parseo de escapes de `printf` — verificado
de nuevo con `cat -A`, ahora produce exactamente los bytes esperados.

**Pendiente de verificar** (no se puede comprobar sin verlo renderizado en el visor de logs real
del Supervisor, que esta sesión no puede tocar): si el hyperlink OSC 8 se muestra como link
clicable de verdad, o si el visor simplemente lo ignora y muestra solo el texto plano/coloreado
de la URL (comportamiento esperado y aceptable en cualquiera de los dos casos — la secuencia está
bien formada, con terminador ST correcto, así que un visor que no la entienda debería consumirla
en silencio sin mostrar bytes de escape en crudo, pero esto no se ha confirmado visualmente).
Si tras desplegar se ve algo raro (bytes de escape visibles en vez de texto limpio), avisad y se
quita el envoltorio OSC 8, dejando solo el color (confirmado que ese sí funciona).

**Addendum (2026-07-10)**: al desplegar, "Reiniciar" el add-on NO recogió el `run.sh` nuevo — el
log salió idéntico al anterior. Causa probable: sin subir `version` en `config.json`, el
Supervisor no tiene forma de saber que hay una imagen nueva que reconstruir, así que sigue usando
la ya construida. Corregido: `version` subido de `0.1.0` a `0.2.0` (bump por feature nueva
visible, no solo parche) y añadido `CHANGELOG.md` en la raíz del add-on (formato real verificado
contra el repo oficial de add-ons de HA — `home-assistant/addons`, ejemplo `configurator`:
encabezados `## X.Y.Z`, más reciente primero, lista de bullets por versión) con las entradas de
`0.1.0` (release inicial) y `0.2.0` (esta mejora del log). El enlace "Registro de cambios" de la
página del add-on lee este fichero automáticamente, sin ningún campo adicional que tocar en
`config.json`. Con la versión subida, el flujo esperado ahora es "Actualizar" en vez de
"Reconstruir" a ciegas.

---

## 🟢 Q13 — `device_name` sobrescrito por un nombre fijo de la integración (2026-07-09) — CORREGIDO

Petición del usuario (misma pieza que firmware_cloud está resolviendo del lado del payload
`dev.name` de la MQTT discovery): el nombre mostrado del dispositivo en HA no reflejaba el
`device_name` configurado en el propio doorbell — se veía "IG Doorbell v2" en su lugar.

**Causa confirmada investigando la API real de `device_registry.async_get_or_create` de HA**
(no asumida — verificada contra el código fuente actual de HA Core): el parámetro `name` de esa
llamada, si se pasa explícitamente, **sobrescribe** el nombre guardado del dispositivo en CADA
llamada (arranque, recarga, reinicio) — sin importar si el dispositivo ya tenía un nombre puesto
por otra integración. Nuestro `__init__.py::async_setup_entry` pasaba `name=entry.title` en cada
llamada — con el fix de fusión de identifiers (Q11), este dispositivo ahora es el MISMO que
registra la integración `mqtt` con el `device_name` real del payload `dev.name` del firmware, así
que las dos llamadas competían por poner el nombre — "quien registre/recargue último, gana". Con
`entry.title` siendo solo un hint (nombre de mDNS o, en alta manual, el `device_id` en crudo, ver
`config_flow.py`), cualquier reinicio/recarga de NUESTRA integración después de que MQTT hubiera
puesto el nombre real lo devolvía a ese hint.

**Corregido**: `async_get_or_create()` ya NO pasa `name=` en absoluto. Confirmado en el código
fuente de HA que esto es seguro y hace justo lo que hace falta: si el dispositivo es nuevo (nunca
visto), HA le pone por defecto el título de nuestro propio config entry (mismo resultado que
antes en el peor caso — nunca queda sin nombre); pero si el dispositivo YA existe (p. ej. porque
la MQTT discovery del firmware ya registró su `device_name` real), omitir `name` significa que
nuestra llamada **nunca vuelve a tocar el nombre existente** — solo el `mqtt` integration, con el
`device_name` real que firmware_cloud está añadiendo al payload `dev.name`, seguirá siendo la
única fuente que lo actualiza a partir de ahora.

Sintaxis re-verificada. Sin cambios en `manufacturer`/`model` (siguen fijos, "Islautopia"/"IG
Doorbell") — no es lo que se pidió, y al ser metadatos estáticos sin un "valor correcto según el
usuario" real detrás (a diferencia del nombre), el mismo riesgo de last-write-wins entre
integraciones existe pero es de impacto cosmético mucho menor; no se ha tocado.

Coordinación con firmware_cloud: confirmar el formato final de `dev.name` en el payload MQTT
(campo `"name"` dentro del bloque `"dev":{...}` de cada discovery config, con fallback si
`device_name` está vacío) — nuestro lado no necesita saber el valor exacto del fallback, solo que
el campo se llame `name` dentro de `dev`, que es lo único que el `mqtt` integration de HA lee
para el nombre del dispositivo.

---

## ⚪ TODO aparcado — Entidad `camera` nativa vía WebRTC en `islautopia_doorbell` (2026-07-09)

**Decisión del usuario, textual**: *"Aparcamos la creación de la entidad ahora. La dejamos en un
TODO de cosas que tal vez haremos algún día … o tal vez no"*. Ni el puente `aiortc` ni la vía
RTSP-bajo-demanda se construyen por ahora. Se deja aquí la investigación completa ya hecha para
que, si se retoma algún día, no haga falta rehacerla desde cero.

**Motivación original**: dar al doorbell una entidad `camera` nativa en HA (visible en cualquier
dashboard/tarjeta estándar de HA, no solo en la card personalizada), evitando el pipeline
genérico HLS/`stream` de HA (percibido como lento) y, si fuera posible, sin que Home Assistant
tuviera que estar en el camino del propio vídeo (solo de la señalización).

**Hallazgo crítico, verificado contra el código fuente/documentación real de HA Core (no
asumido)**: la API moderna de cámara WebRTC de HA (`Camera.async_handle_async_webrtc_offer` +
`async_on_webrtc_candidate` + `close_webrtc_session`, con soporte de `CameraEntityFeature.STREAM`)
asume que **el FRONTEND de HA genera la oferta SDP y la entidad `camera` genera la respuesta** —
navegador ofrece, cámara responde. El doorbell es exactamente lo contrario: es ICE-Lite y **solo
emite ofertas** (`webrtc_generate_offer()` en `main/webrtc_task.c`), nunca procesa una oferta
entrante para generar una respuesta — limitación real y deliberada del firmware (simplificar su
propio stack WebRTC), no una limitación general de ICE-Lite como protocolo.

**Consecuencia**: la esperanza de "HA solo como intermediario de señalización, el navegador
negocia directo contra el doorbell/relay, sin vídeo pasando por HA" **no es alcanzable de forma
limpia** con el firmware tal cual está hoy. Se evaluó en detalle intentar "traducir" la oferta
real del doorbell en una respuesta sintética para la oferta que genera el frontend de HA — riesgo
alto de incompatibilidad real de SDP: un navegador genérico por defecto ofrece códecs como
VP8/VP9/Opus salvo que se le fuerce a limitarse a H264/PCMA (lo único que el doorbell entiende, y
no hay garantía de poder controlar eso desde una integración de cámara de HA), más diferencias de
roles ICE/DTLS (`a=setup:actpass/active/passive`) que el doorbell nunca fue diseñado para
negociar en el lado de respuesta. No descartado al 100% sin probarlo en real, pero valorado como
un camino frágil y de alto riesgo de fallo silencioso/intermitente, no una solución robusta.

**Único camino realista identificado**: un puente de medios real dentro de la integración
(típicamente con `aiortc`, la librería WebRTC de Python) — la integración actuaría como DOS peers
WebRTC simultáneos: uno respondiendo de verdad al frontend de HA (su contrato oferta/respuesta),
y otro hablando con el doorbell exactamente como ya hace la card (recibe SU oferta, genera
respuesta, intercambia candidatos, mismo flujo que `tryLocalSignaling()`/`startRelaySignaling()`
en `islautopia-intercom-card.js`) — retransmitiendo los paquetes RTP entre ambas sesiones ya
negociadas. Sigue siendo mejor que el pipeline HLS/genérico (WebRTC de punta a punta en ambos
tramos, no transcodificación a segmentos), pero **HA SÍ queda en el camino del vídeo**, no solo de
la señalización — al contrario de la esperanza original. Para que sea realmente rápido (no lento
por otro motivo distinto a HLS) haría falta trabajar con las APIs de bajo nivel de `aiortc` para
reenviar paquetes RTP tal cual sin decodificar/recodificar (su API de alto nivel decodifica y
recodifica por defecto, caro de CPU y con pérdida) — riesgo técnico real, no solo de esfuerzo.

**Restricciones ya resueltas para cuando se retome** (no hace falta re-investigarlas):
- **Pool de sesiones**: se respeta de forma natural en cualquiera de los dos diseños — el tramo
  hacia el doorbell usa el mismo canal de señalización que ya usa la card (local con `?token=`, o
  remoto vía relay), consumiendo un slot del mismo pool compartido `MAX_WEBRTC_SESSIONS=2` como
  cualquier otro cliente. Solo hace falta propagar un `sessions_full` como error claro hacia el
  frontend de HA en vez de dejarlo colgado — sin diseño especial de sesión necesario.

**Valoración de esfuerzo/riesgo (para cuando se decida retomarlo o no)**: sustancialmente más
grande que cualquier otra pieza construida hasta ahora en este lado del proyecto — nueva
dependencia pesada (`aiortc`, con librerías nativas de códec/cripto), reversión real del principio
de diseño "la integración no hace de proxy de medios" (`ARCHITECTURE.md` §3), uso de CPU/red real
dentro del propio proceso de HA Core mientras la cámara esté activa (relevante en hardware modesto
tipo Raspberry Pi), y el riesgo técnico concreto del passthrough RTP sin recodificar.

**Alternativa más barata considerada, tampoco construida**: entidad `camera` genérica sobre RTSP
(`rtsp_en=1`, activado por la propia integración solo mientras hay streaming activo — vía
`POST /save` con sesión transitoria — y desactivado al terminar, para no dejar el puerto RTSP
abierto permanentemente, que era la objeción original del usuario a la vía RTSP). HA Core trae su
propio `go2rtc` embebido que da WebRTC automático a cualquier cámara con fuente RTSP, sin que
nuestra integración tenga que implementar nada de WebRTC — mucho más barato, pero sigue exigiendo
tocar `rtsp_en` en el doorbell (aunque sea de forma acotada/temporal) y añadir de nuevo un camino
RTSP que el resto del proyecto ha evitado deliberadamente. No evaluada en más profundidad al
aparcarse la pieza entera.

---

## 🟢 Verificación de extremo a extremo completa en HA real (2026-07-10) — CIERRE de esta ronda

Confirmado por el líder: card añadida al panel real "IG Doorbell p4 v2", dispositivo fusionado
"IG Doorbell v2" seleccionado con el picker nativo (`ha-selector`, funcionando perfectamente —
confirma que la fusión de identifiers, Q11, y el fix de no pisar el nombre, Q13, son correctos) y
**vídeo en vivo real renderizando en la card embebida en HA**. Primera prueba de extremo a
extremo con éxito de todo lo construido en esta ronda (integración + card + add-on HTTPS).

**Hallazgo real durante la prueba, ya trasladado a firmware_cloud (no accionable de nuestro
lado)**: la card intenta primero el camino LOCAL directo, pero el navegador lo bloquea por CORS —
el HTTPS del doorbell en `:8443` no manda `Access-Control-Allow-Origin`, y el origen de la página
de HA es distinto del origen del doorbell. Cae automáticamente al camino REMOTO vía relay (que sí
funciona, de ahí que el resultado visible fuera correcto), pero significa que, embebida en HA, la
card usa siempre el camino más lento hasta que el firmware añada esa cabecera.

**Mejora de diagnóstico aplicada** (sugerida como no urgente, implementada de todas formas por ser
barata y quedar todo fresco): `tryLocalSignaling()` en `islautopia-intercom-card.js` ahora deja un
`console.warn` más informativo cuando el camino local falla, mencionando CORS como motivo más
probable y señalando la pestaña Network/Console de las DevTools como el único sitio donde el
navegador sí expone el motivo real. **Precisión técnica importante, no exagerar la mejora**: ni
`EventSource.onerror` ni `fetch()` exponen desde JavaScript si un fallo fue por CORS o por
cualquier otro motivo de red — es una limitación deliberada de seguridad de los navegadores, no
una limitación nuestra — así que el aviso nuevo *sugiere* la causa más probable dado este hallazgo
real, no la *confirma* de forma programática. Sintaxis verificada con `node --check`.

---

## 🟡 Q15 — Reporte real de 10+s para el primer frame (vs. ~1s con la card antigua) — investigado, un bug ya corregido, resto instrumentado, cambio de arquitectura pendiente de datos reales

Reporte del usuario, probado dos veces (URL local del addon HTTPS y dominio externo): la card
nueva tarda 10+ segundos en arrancar el stream, frente a ~1s de la card antigua vía go2rtc — sin
sentido, ya que se quitó un hop (go2rtc) y una recodificación. Un script de prueba en crudo
(Playwright, `RTCPeerConnection` real, Fase 25 del plan de firmware) tardaba solo 1.3-1.8s en las
mismas condiciones, así que el protocolo del doorbell/relay no es el cuello de botella.

### Bug real encontrado y corregido de inmediato (alta confianza, sin necesitar medirlo primero)

`websocket_get_connection_info` (`websocket_api.py`) llamaba a
`discovery.async_resolve_local_host()`, que podía bloquear **hasta 4 segundos** en un browse mDNS
en vivo (`_BROWSE_TIMEOUT`) cada vez que la cache (60s TTL) estaba vacía o caducada — y esto pasa
en la ruta caliente de **cada arranque de sesión** de la card (`get_connection_info` es la primera
llamada de `startNativeSession()`). El problema real: el valor que se estaba esperando
(`local_host`) **ni siquiera lo usa la card** para construir su URL de conexión (ya lo dejamos
anotado en la Q7 — la card siempre conecta por el hostname público, nunca por la IP de mDNS, tanto
por el certificado como por CORS/mixed-content). Es decir: hasta 4 segundos completamente tirados
esperando un dato que no se iba a usar.

**Corregido** en `discovery.py`: `async_resolve_local_host()` ya NUNCA bloquea en un browse en
vivo — devuelve inmediatamente lo que haya en cache (o `None`) y lanza el refresco de mDNS en
background (`hass.async_create_task`), sin que el llamador lo espere. La cache se sigue
actualizando igual para la próxima vez, solo que ya no bloquea la sesión actual.

### Instrumentación real con timestamps, añadida para medir el resto (pedida explícitamente, no adivinar)

- **Backend** (`websocket_api.py`): `get_connection_info` y `get_turn_credentials` loggean su
  tiempo real de respuesta a nivel `INFO` (fácil de encontrar en Registros de HA sin subir el log
  level) — `[islautopia_doorbell timing] get_connection_info para <id>: <N>ms`.
- **Card** (`islautopia-intercom-card.js`): nuevo método `_mark(label)` que deja en la consola del
  navegador cada paso con el tiempo transcurrido desde el inicio de esa sesión concreta
  (`performance.now()`), cubriendo: inicio de sesión, respuesta de `get_connection_info`, respuesta
  de `get_turn_credentials`, PC construida, inicio/fin del intento local (con el motivo si falla:
  timeout de 3000ms agotado, excepción al crear `EventSource`, oferta recibida), inicio del intento
  remoto si aplica (WS abierto, `request_offer` enviado), procesado de la oferta SDP y envío de la
  respuesta, cada transición de `RTCPeerConnection.connectionState`, y el **primer frame realmente
  pintado en pantalla** (`requestVideoFrameCallback`, más preciso que `pc.ontrack` — éste solo
  marca cuando llega el stream a nivel de transporte, no cuando se ve algo de verdad; con fallback
  a `loadeddata` si el navegador no soporta `requestVideoFrameCallback`).

Sintaxis verificada en ambos repos (`python -m py_compile`, `node --check`). **Pendiente de
desplegar y volver a probar** para tener los números reales — con esto ya no hace falta adivinar
nada del resto de la secuencia.

### Análisis de la propuesta del usuario ("race" tipo Happy Eyeballs) + hallazgo relacionado sobre el badge en rojo

Confirmado leyendo el código (no solo intuido): la secuencia hoy es **estrictamente secuencial**
— `startNativeSession()` espera a que `tryLocalSignaling()` termine del todo (éxito, o los 3000ms
de timeout fijo agotados) antes de siquiera empezar `startRelaySignaling()`. En el peor caso
(local no disponible del todo), eso son 3000ms muertos garantizados antes de que arranque el
intento remoto — de acuerdo en que esto **sí** puede ser una parte real del problema, aunque no
la única (con el hallazgo del mDNS ya sumamos hasta 4s más, y aún queda por medir el resto).

**Hallazgo adicional, relacionado con el bug de UX del badge en rojo que señaló el usuario, más
serio que un simple problema cosmético de cuándo se pinta el rojo**: `tryLocalSignaling()`
considera "éxito" (y por tanto NUNCA intenta el remoto) en cuanto llega una **oferta SDP** por
SSE — no cuando la conexión ICE/DTLS realmente se establece. Con el CORS ya arreglado por
firmware_cloud, es perfectamente posible que la señalización local funcione (llega la oferta, se
manda la respuesta) pero que la conexión real por la ruta local falle después (red local no
alcanzable por algún motivo aunque el HTTPS de señalización sí lo sea) — en ese caso,
`RTCPeerConnection.connectionState` pasa a `failed`/`disconnected`, el badge se pone en rojo, **y
el diseño actual no tiene ningún plan B**: ya se dio por buena la vía local a nivel de
señalización y nunca se intenta el relay remoto como alternativa real. Sospecho que esto explica
mejor lo que describe el usuario ("se pone en rojo durante lo que debería ser un simple fallback
interno") que un problema meramente cosmético de "cuándo pintamos el rojo" — es un fallo real de
recuperación, no solo de UI. Añadido `_mark()` en `onconnectionstatechange` para confirmarlo con
datos la próxima vez que pase.

**Sobre la propuesta de "race" en paralelo (Happy Eyeballs)**: de acuerdo en que es un patrón
sólido y bien establecido (RFC 8305), y resolvería estructuralmente el problema de "esperar una
espera larga antes de la alternativa" — pero con dos matices reales a tener en cuenta antes de
comprometerse a construirlo, no descubiertos hasta mirar el código de cerca:

1. **No se puede "correr" un único `RTCPeerConnection` contra dos ofertas a la vez** — cada `pc`
   solo puede tener una `remoteDescription` activa. Un race real necesitaría DOS instancias de
   `RTCPeerConnection` (una por candidato de ruta: local y remoto), quedarse con la que llegue
   primero a `connectionState:"connected"` (no solo la que responda primero a nivel de
   señalización — eso evitaría también el bug del punto anterior, ya que "ganar la carrera" se
   definiría por conexión real, no por señalización), y cerrar/descartar la otra.
2. **Coste de slots de sesión**: lanzar señalización local Y remota a la vez para un solo
   espectador consume momentáneamente hasta 2 de los 2 slots totales de `MAX_WEBRTC_SESSIONS=2`
   del propio doorbell — si ya hay otro espectador activo en ese momento, el segundo intento del
   race podría recibir `sessions_full` en vez de conectar limpiamente. Antes de construirlo,
   merece la pena decidir si el race es "desde el segundo 0" o si se le da al local una ventana
   corta (unos cientos de ms, ahora que CORS está arreglado un local sano debería responder rápido)
   antes de lanzar el remoto en paralelo — un punto intermedio que reduce el riesgo de agotar
   slots sin perder casi nada de la ventaja de velocidad.

**No implementado el race todavía**, tal como se pidió — primero los números reales con la
instrumentación ya desplegada, luego se decide la forma exacta (race completo desde el inicio,
race con ventana corta, o simplemente arreglar el bug de "éxito prematuro" del punto anterior y
bajar el timeout fijo de 3000ms ahora que CORS ya no debería tardar tanto en fallar cuando
corresponda) con datos delante en vez de a ciegas.

---

## 🟢 Q16 — `local_host`/mDNS eliminado por completo del camino de conexión (2026-07-10) — CERRADO

Tras el hallazgo del bug de los 4s (Q15), el usuario preguntó el motivo histórico de por qué
`get_connection_info` pedía `local_host` si nunca se usaba para conectar. Repasado el propio
historial de diseño de esta sesión (no adivinado): es un vestigio real de un pivote — el plan
original SÍ era que la card usara `local_host` para conectar (primer borrador de
`ARCHITECTURE.md` §4.3), hasta que al escribir la card de verdad se descubrió (Q7) que el
certificado real del doorbell obliga a conectar siempre por hostname, nunca por IP. Se actualizó
la card en su momento pero nunca se limpió el backend que ya no hacía falta — eso es lo que causó
el bloqueo de 4s.

Confirmado con grep en los tres repos: ningún consumidor real de `local_host` aparte de la propia
card (que ya no lo usa). El usuario añadió un argumento de peso adicional para no dejarlo ni
siquiera como campo informativo: **mDNS es multicast y normalmente no cruza límites de VLAN/
subred sin un relay explícito** — para cualquier instalación con segmentación de red real (su
propio caso, con doorbells aprovisionados manualmente por IP en una VLAN distinta a la de HA),
confiar en mDNS para esto sería activamente incorrecto, no solo inútil.

**Eliminado por completo**, confirmado por el usuario ("sí, adelante con la limpieza"):
- `discovery.py` borrado entero (el módulo de mDNS: caché, browse en background — ~110 líneas).
- `local_host` quitado de la respuesta de `get_connection_info` (`websocket_api.py`) — ya no
  llama a ningún resolutor LAN en absoluto.
- `ZEROCONF_SERVICE_TYPE` quitado de `const.py` (quedaba sin usar tras borrar `discovery.py` —
  el descubrimiento de emparejamiento en `config_flow.py::async_step_zeroconf` no lo necesitaba
  como constante Python, lo activa `manifest.json` directamente).
- `CONF_HOST_HINT` **se mantiene** (capturado en `config_flow.py` al emparejar) — barato, sin
  coste en tiempo de ejecución, útil algún día para soporte/diagnóstico manual aunque hoy no
  tenga consumidor activo. El descubrimiento de emparejamiento por Zeroconf (`async_step_zeroconf`)
  tampoco se toca — es puramente opcional/oportunista, con la entrada manual por IP siempre
  disponible como alternativa real, así que no comparte el mismo problema de "activamente
  incorrecto" que sí tenía la resolución en caliente de `local_host`.

**Verificación de regresión**: `python -m py_compile` limpio en los 8 ficheros restantes de la
integración (confirmado que no queda ningún `import discovery` ni referencia a `local_host` en
código, solo en comentarios explicativos), `node --check` limpio en la card (nunca llegó a leer
`info.local_host`, cero cambios necesarios ahí). `__pycache__` local con el `.pyc` obsoleto de
`discovery.py` limpiado de paso. Nada commiteado — a la espera de agruparlo con el próximo lote.

---

## 🟡 Q17 — El bug de "sin entidades" (Q11) reapareció tras el despliegue del lote de mDNS — en investigación con datos reales, no descartado a ciegas

Tras desplegar Q15/Q16 (reinicio completo de HA incluido), "IG Doorbell v2" volvió a mostrar "sin
entidades" — el mismo síntoma de Q11. Mismo `device_id` de siempre
(`e2a9850338a9c55ee6e7733c0e0503ab`), confirmado un único dispositivo en el listado, no un
duplicado. Sin errores de `islautopia_doorbell` en Registros tras borrar `discovery.py` — el
import queda limpio.

**Descartado, verificado, no asumido**:
- El `__init__.py` de este repo SIGUE teniendo el fix de fusión de identifiers de Q11 intacto —
  releído línea por línea, `identifiers={(DOMAIN, entry.data[CONF_DEVICE_ID]),
  ("mqtt", mqtt_ident)}` presente y correcto, sin que el fix de Q13 (quitar `name=`) lo haya
  tocado por error.
- La semántica de merge de `identifiers` en `device_registry.async_get_or_create()` — verificada
  contra el código fuente real de HA Core, no asumida: los identifiers se **fusionan por unión**
  (`old_identifiers | merge_identifiers`) sin importar qué integración/config_entry llame primero,
  y `config_entries` (qué integraciones están vinculadas al device) tampoco tiene ningún scoping
  que pudiera romper esto. El mecanismo en el que se apoya el fix de Q11 es sólido según la propia
  documentación/código de HA — no es una limitación de la API la que está fallando aquí.

Con el código y el mecanismo ya descartados como causa, hace falta ver datos reales de ESTE
arranque en concreto para saber qué pasó. **Añadida instrumentación de diagnóstico** en
`__init__.py::async_setup_entry` — tras la llamada a `async_get_or_create()`, un log a nivel INFO
con el device resultante completo: `id`, `name`, `name_by_user`, `identifiers` y `config_entries`
— esto dirá directamente si la fusión ocurrió a nivel de registro (¿aparecen los dos
`config_entries`, el nuestro y el de `mqtt`?) o si sigue habiendo dos devices separados por algún
motivo no evidente todavía (p. ej. timing en el arranque, o algo del lado MQTT/discovery que
escapa a nuestro código).

**Hipótesis a confirmar o descartar con el log nuevo, en orden de probabilidad, ninguna asumida
como cierta**:
1. Fallo de copia/despliegue (fichero real distinto al que se verificó) — descartable pidiendo
   abrir el `__init__.py` desplegado y comparar visualmente el bloque `identifiers={...}`.
2. Timing de arranque: si las entidades de MQTT discovery no llegan a tiempo tras el reinicio
   completo (reconexión al broker, mensajes retenidos) tal vez el device de `mqtt` no se cree (o
   se elimine y recree) de una forma que rompa el merge — el log de diagnóstico lo confirmaría
   por el campo `config_entries` del device resultante.
3. Algo específico de un REINICIO COMPLETO frente a una simple recarga de la integración (la
   prueba de ayer que sí funcionó fue tras un despliegue distinto) — no descartado, sin datos
   para confirmarlo o negarlo todavía.

**Siguiente paso**: redesplegar `__init__.py` (único fichero cambiado en este turno) + reiniciar,
y mirar en Registros la línea `[islautopia_doorbell diag] device tras async_get_or_create: ...`.
Con eso se sabrá con certeza en qué punto se rompe, en vez de seguir descartando hipótesis a
ciegas. Sintaxis verificada (`python -m py_compile`), nada commiteado.

**Addendum (2026-07-10) — la propia línea de diagnóstico desapareció sin dejar rastro**: subido
`custom_components.islautopia_doorbell` a `debug` en caliente (`logger.set_level`, sin tocar
`configuration.yaml`) y recargada la integración — el `mqtt_dispatch` (código que corre
justo DESPUÉS del bloque de diagnóstico, dentro de la misma función) sí logueó con normalidad a
los timestamps esperados, pero la línea `[islautopia_doorbell diag] ...` no apareció en ningún
sitio del log completo descargado, sin ninguna excepción/traceback visible alrededor tampoco.
Confirmado además que el `__init__.py` real desplegado en el host tiene la línea exacta (`grep`
directo al fichero real, no a la copia local).

**Diagnóstico**: como el código posterior SÍ se ejecuta con normalidad, se descarta una excepción
en la evaluación de los argumentos del log (eso habría abortado toda la función, y
`async_ensure_door_action_listener` no habría llegado a correr). El sospechoso más probable:
Python `logging` formatea los `%s`/`%r` de forma DIFERIDA — solo al emitir el registro, no al
llamar — y si esa fase de formateo falla, `Handler.handleError()` lo captura y lo manda a
`stderr` (nunca al fichero `home-assistant.log`), sin propagar la excepción y sin que el resto
del código se entere. Encajaría con lo observado: cero rastro en el log, cero corte de ejecución.

**Corregido para eliminar la incertidumbre, no solo re-intentado a ciegas**: el mensaje de
diagnóstico ahora se construye entero como una única cadena de texto plano (f-strings + `sorted()`
+ `str()` explícitos sobre cada valor) ANTES de llamar a `_LOGGER.info()`, con un
`try`/`except` alrededor — si algo revienta construyendo el mensaje, se loguea ESE error en su
lugar (visible, no silencioso). Sin argumentos de formateo diferido (`_LOGGER.info(diag_msg)`,
una sola cadena ya completa) — `record.getMessage()` con `args` vacío ni siquiera intenta el
`%`-formatting, así que esta clase de fallo queda estructuralmente descartada. Verificado
localmente con objetos simulados que imitan los tipos reales de `DeviceEntry`
(`id: str, name: str|None, name_by_user: str|None, identifiers: set[tuple], config_entries:
set[str]`) — construcción limpia, sin excepción, salida legible.

Pendiente: redesplegar (mismo `__init__.py`, único fichero cambiado) y volver a mirar el log —
esta vez debería aparecer sí o sí, o al menos el mensaje de fallback del `except` si algo sigue
sin encajar. Sintaxis verificada de nuevo, nada commiteado.

---

## 🟢 Q18 — La card no liberaba el slot al cerrar/recargar la pestaña — CORREGIDO, dos bugs reales

Pregunta del líder, relacionada con el agotamiento de slots reportado por el usuario: ¿replica la
card el patrón `pagehide`+`sendBeacon` que ya usa el dashboard web del propio doorbell para
liberar el slot al instante en vez de esperar el timeout de abandono (~45s)? Verificado contra el
código real, no de memoria (`grep` en todo el fichero): **no lo replicaba** — cero coincidencias
de `pagehide`, `sendBeacon`, `beforeunload` o `visibilitychange` en toda la card. Solo existía
`disconnectedCallback()` (hook de ciclo de vida de Custom Elements), fiable cuando HA quita la
card del DOM al cambiar de vista de Lovelace dentro de la misma página, pero **no garantizado**
durante cierre de pestaña/ventana o recarga completa — el runtime de JS puede desaparecer antes
de que ese hook llegue a ejecutarse.

**Segundo bug encontrado de paso, al revisar `disconnectedCallback()` de cerca**: el camino local
(`nativeSSE`) se cerraba SIN mandar `bye` primero — solo el camino remoto (`nativeWS`) lo hacía.
Es decir, incluso en el caso "normal" ya cubierto (cambiar de vista de Lovelace), una sesión local
activa dejaba el slot ocupado hasta el timeout de abandono en vez de liberarlo al instante.

**Corregido, ambos bugs**:
- `disconnectedCallback()` ahora manda `bye` también para el camino local antes de cerrar
  `nativeSSE` (mismo patrón que ya tenía el camino remoto).
- Nuevo `pagehide` a nivel de `window` (no del elemento — registrado en `startNativeSession()`,
  desregistrado en `disconnectedCallback()` para no acumular listeners si la card se reconecta):
  para el camino local usa `navigator.sendBeacon()` en vez de `fetch()` (un `fetch()` en marcha se
  cancela al desaparecer la página; `sendBeacon` está diseñado específicamente para completarse
  durante el unload — el `Content-Type: application/json` se consigue pasando un `Blob` con ese
  `type`, ya que `sendBeacon` no admite cabeceras propias). Para el camino remoto, `sendBeacon` no
  aplica a WebSocket — un `nativeWS.send()` síncrono sobre la conexión ya abierta es lo mejor
  disponible, mismo mecanismo que ya usaba `disconnectedCallback()`.

**Deliberadamente NO se añadió `visibilitychange`**: cambiar de pestaña del navegador (sin cerrar
la página) NO debe cortar la sesión — sería un cambio de comportamiento no pedido y peor UX que lo
que ya existe hoy (el propio README ya documenta "cierre limpio al salir de la pestaña de
Lovelace", refiriéndose a cambiar de VISTA dentro de HA, no de pestaña del navegador). Solo
`pagehide` (cierre/recarga/navegación fuera de la página) y el fix de `disconnectedCallback()`.

Sintaxis verificada (`node --check`), nada commiteado.

---

## 🟢 Q19 — Vigilante de "señales de vida" + reconexión automática (2026-07-10) — IMPLEMENTADO

Diseño simétrico con el firmware, que baja su propio timeout de abandono de 45s a 20s: el lado
consumidor (la card) también debe dejar de esperar pasivamente y actuar si la sesión lleva ~20s
sin ninguna señal de vida real, en vez de quedarse colgada indefinidamente.

**Diseño aprobado y luego ajustado por el usuario a un criterio más agresivo** (mismo criterio al
que llegó independientemente `android_app` para su propio watchdog, sin coordinarse entre
equipos — refuerza que es la decisión correcta):

1. **Señal primaria: `getStats()` sobre el track de vídeo**, no el estado de ICE del navegador.
   Cada 5s, `_checkLifeWatchdog()` llama a `pc.getStats()`, busca la entrada `inbound-rtp` de
   kind `video`, y compara `packetsReceived` (con `framesReceived` como fallback si el navegador
   no expone el primero) contra la lectura anterior — si subió, hay señal de vida real. Se
   descartó depender solo de `connectionState`/`iceConnectionState` porque esos los gobierna el
   propio navegador con sus checks de "consent freshness" (RFC 7675) — pueden seguir en
   `connected` aunque el vídeo se haya parado por otro motivo, y el tiempo que tarda cada
   navegador en marcarlos como caídos no es ajustable a los 20s exactos que pide el diseño.
2. **Señal secundaria, para la fase de negociación ANTES de que haya vídeo**: cualquier mensaje
   de señalización recibido (oferta/candidato/heartbeat, tanto local por SSE como remoto por WS)
   también cuenta como señal de vida — cierra además un hueco real encontrado al diseñar esto:
   hoy no había NINGÚN timeout esperando la oferta tras `request_offer` en el camino remoto; si
   el relay/doorbell nunca respondía, la card se quedaba colgada sin más.
3. **Atajo AGRESIVO, decisión explícita del usuario tras la propuesta inicial** (que solo
   contemplaba `failed` como atajo inmediato): tanto `failed` **como `disconnected`** en
   `pc.onconnectionstatechange` disparan reconexión inmediata, sin esperar el resto del
   cronómetro de 20s — a sabiendas de que `disconnected` puede ser transitorio y esto podría
   interrumpir alguna recuperación normal de vez en cuando. Decisión consciente para validarla en
   condiciones reales de cobertura 4G/5G mala (fase de pruebas "bajo fuego real" pendiente, no
   parte de este cambio). El chequeo de `getStats()` del punto 1 queda como respaldo para el caso
   que ese atajo NO cubre: transporte aparentemente sano (`connectionState` sigue en `connected`)
   pero sin datos reales llegando.
4. **Reconexión — reutilizando la lógica existente, sin duplicar código**: nuevo método
   `_teardownConnectionObjects()`, extraído de lo que antes solo tenía `disconnectedCallback()`
   (cierra `pc`/`nativeSSE`/`nativeWS`, manda `bye` antes cuando aplica, resetea el slot, para el
   vigilante) — usado ahora por `disconnectedCallback()`, `startWebRTC()` (defensivo) y el nuevo
   `_scheduleReconnect()`, que hace la limpieza y programa una nueva llamada a `startWebRTC()` (el
   mismo punto de entrada de la conexión inicial — vuelve a intentar local-primero-luego-remoto
   desde cero) con backoff simple (2s, 4s, 8s, tope en 15s — verificado con una simulación
   aislada de la fórmula, sin depender de probarlo en real para confirmar los números). Reintentos
   **indefinidos** por defecto (decisión ya tomada: para un producto de seguridad doméstica, mejor
   seguir intentándolo en silencio que dejar la card muerta hasta que el usuario recargue a mano)
   — el contador de reintentos se resetea a 0 en `setupRemoteStream()`, en cuanto un reconecto
   trae vídeo de vuelta de verdad, no solo señalización.
5. **`bye` recibido del propio dispositivo** (p. ej. sesión desplazada por otra) también dispara
   reconexión ahora, en vez de solo pintar el badge en rojo y quedarse así — mismo mecanismo.
6. **Feedback visual**: durante la reconexión, badge a "Conectando..." (clave i18n existente) y
   el loader reaparece — sin marcarlo en rojo, ya que es un ciclo de recuperación normal, no un
   fallo terminal.
7. **Alcance**: solo modo `native` (`_scheduleReconnect()` comprueba `this.mode !== 'native'` y
   no hace nada si no aplica) — el modo `go2rtc` legacy no forma parte de este diseño.

**Verificación realizada sin acceso a un navegador/HA real** (no disponible en esta sesión):
`node --check` para sintaxis, y una simulación aislada en Node de la lógica pura (fórmula de
backoff para 6 intentos consecutivos, y el parseo de un `RTCStatsReport` simulado con
`packetsReceived`/`framesReceived`/sin entrada de vídeo) — ambas se comportan exactamente como
especifica el diseño. **Pendiente de la validación real que el propio usuario quiere hacer bajo
su cobertura 4G/5G mala** — eso decidirá si el criterio agresivo (`disconnected` inmediato) acierta
en la práctica o si conviene suavizarlo más adelante.

---

## 🟢 Q20 — Cambio de dominio del accionador de apertura (`button`→`light`/`switch`) — sin impacto en la card, más un bug real encontrado de paso

El líder avisó que el accionador de apertura publicado por el firmware cambia de dominio
(`button` → `light` o `switch`, a elegir por firmware_cloud) y preguntó si afecta a la card.

**Respuesta, verificada contra el código real de `triggerUnlock()`**: no hace falta ningún
cambio, en ninguno de los dos casos. `unlock_entity` es un campo de configuración manual (el
usuario apunta a CUALQUIER entidad de su elección, nunca auto-enlazado a la entidad concreta que
publique el firmware) y el código YA trata `switch` y `light` de forma idéntica —
`callService(domain, 'turn_on', ...)` al abrir y `callService(domain, 'turn_off', ...)` tras el
temporizador de auto-cierre, para ambos dominios por igual. Elija firmware_cloud el que elija,
el comportamiento de la card no cambia ni una línea.

**Bug real encontrado de paso, no relacionado con el cambio de dominio pero sí con el mismo
bloque de código**: el README/config de la card ya anunciaba `cover` como dominio soportado para
`unlock_entity` (útil para verjas/portones que usan ese dominio en HA) pero el código nunca tuvo
un caso específico — caía al `else` y llamaba a `cover.turn_on`, un servicio que **no existe** en
el dominio `cover` de HA (verificado contra la documentación real de HA antes de tocar nada, no
asumido: `cover` usa `open_cover`/`close_cover`/`stop_cover`, nunca `turn_on`/`turn_off` — llamar
a `turn_on` ahí lanza `ServiceNotFound`). Cualquier usuario que hubiera configurado de verdad una
entidad `cover` aquí habría visto fallar la apertura en silencio (error solo visible en el log de
HA, sin ningún feedback en la propia card). **Corregido**: `cover` ahora usa `open_cover` al
abrir y `close_cover` tras el temporizador, igual de explícito que el resto de dominios.

Sintaxis verificada (`node --check`), nada commiteado.

---

## 🟢 Q21 — Respuestas automáticas de audio: discovery dinámica por slot real, no 10 botones genéricos

Cierra la pregunta de diseño que dejé abierta en el censo (punto 3 del mensaje original, nunca
formalizada aquí como entrada propia — la registro ahora para que quede trazada).

**Decisión del usuario**: la interfaz debe mostrar la lista real de slots de audio (hasta 10) con
la etiqueta que el usuario le puso a cada uno al subirlo — no "Slot 1"/"Slot 2" genéricos. Esa
etiqueta ya existe hoy: `GET /api/list_audios` devuelve `{"<slot>": {"name": "...", "size": N},
...}` (contrato §1.3), el `name=` que se puso al subir. Para la discovery MQTT: leer
`list_audios` (o el equivalente interno del propio firmware) al generar los topics/entidades, y
publicar solo los slots que de verdad tengan audio, con el `name` real como nombre de la entidad
`button` — nunca un bucle fijo de 10 con etiquetas genéricas.

**Esto es trabajo 100% de firmware** (generación de discovery MQTT en C, no algo que viva en
`custom_components/islautopia_doorbell` ni en la card) — coordinado con firmware_cloud, que ya
tiene el resto del encargo de audio en su lado si lo retoman. Nada que construir de mi parte.

**Confirmación de mi lado, sin necesitar ningún cambio de código**: en cuanto el firmware publique
estas entidades `button` nuevas (uno por slot con audio real, con el `dev.ids` compartido igual
que las 5 entidades existentes — mismo mecanismo que ya usa modo/timbre/puerta/persona/abrir),
aparecerán automáticamente en el MISMO dispositivo fusionado en HA (gracias al fix de Q11 — la
integración `islautopia_doorbell` ya registra ese mismo identifier compartido) sin que haga falta
tocar `custom_components/islautopia_doorbell/__init__.py` ni la card para nada. La creación/
retirada dinámica de entidades vía discovery MQTT (publicar solo los slots reales, quitar el
discovery cuando un slot se borra) la gestiona el propio mecanismo estándar de HA — no hay
ningún trabajo adicional de nuestro lado para que esto funcione una vez el firmware lo publique
bien.

---

## 🟢 Q22 — Tres bugs reales reportados por el usuario en la card, los tres CORREGIDOS (2026-07-10)

Tres hallazgos independientes reportados por el usuario en `islautopia-intercom-card`, investigados
y corregidos en el mismo lote. **Verificación realizada sin acceso a un navegador/HA real** (no
disponible en esta sesión, mismo límite ya documentado en Q19): `node --check` para sintaxis +
lectura/razonamiento estructurado del código, contrastado en el caso 2 contra la implementación de
referencia YA verificada en real del dashboard web (`main/webtask.c`, Fase 9, `IG_Doorbell` repo).
**Pendiente de confirmación visual en real por parte del líder/usuario** en los tres casos — doy el
checklist exacto de qué comprobar en cada uno.

**1. El vídeo no escalaba al ajustar el ancho de la card.** Causa real: la card no usa Shadow DOM
(`this.innerHTML` directo sobre el propio elemento, DOM "ligero") y el elemento personalizado en
sí (`<islautopia-intercom-card>`) nunca declaraba su propio `display`/`width` — los Custom
Elements autónomos son `display: inline` por defecto salvo que se declare lo contrario (ni el
navegador ni HA lo hacen por ti), y un elemento `inline` se dimensiona a su contenido, no al
ancho disponible del contenedor. Todo el CSS interno (`.intercom-container`, `.video-wrapper`,
`video { width:100% }`) YA era correcto y relativo — el problema era que "100%" se resolvía
contra un elemento que nunca creció. **Corregido**: `this.style.display='block'; this.style.
width='100%'` fijado en JS dentro de `setConfig()` (aplica de inmediato, antes de que exista
ningún hijo) + regla CSS `islautopia-intercom-card { display:block; width:100% }` en
`injectStyles()` como respaldo defensivo. **Checklist de verificación real**: cambiar el ancho de
la card (p. ej. en un dashboard de tipo "Secciones" de HA, o cualquier contenedor que le dé un
ancho explícito distinto del 100% de la vista) y confirmar que el vídeo escala con ella, sin
quedarse al tamaño antiguo ni recortarse.

**2. Sospecha del usuario: el canal de retorno de audio (mic del navegador → altavoz del
doorbell) podría no llevar audio real, aunque la UI indique "mic activo".** Comparé
`toggleIntercom()`/`buildNativePeerConnection()` de la card contra la implementación YA
verificada en real del dashboard (`dashToggleMic()`/`dashConnect()` en `main/webtask.c`) — el
patrón de pista muda + `replaceTrack()` en sí es funcionalmente idéntico (mismo orden de
creación de transceivers, mismo `getUserMedia`+`replaceTrack` en el gesto de click) y NO es la
causa. **Causa real encontrada, distinta de la sospecha original pero con el mismo síntoma**:
`_teardownConnectionObjects()` — el único punto de cierre compartido por `disconnectedCallback()`,
`startWebRTC()` y `_scheduleReconnect()` (el vigilante de reconexión automática de Q19, recién
implementado ese mismo día) — cerraba `pc`/`nativeSSE`/`nativeWS` pero NUNCA tocaba el estado del
interfono. Efecto real: si el mic estaba activo (el sender ya tenía la pista real del micrófono)
y llegaba una reconexión (p. ej. el atajo agresivo `disconnected`→reconectar de Q19, que puede
dispararse por un corte transitorio de ICE sin que el usuario haga nada), el nuevo
`RTCPeerConnection` se reconstruye desde cero con una pista MUDA nueva — pero como
`intercomActive`/las clases del botón nunca se reseteaban, la UI seguía mostrando "mic activo"
(icono rojo, badge "Comms Abiertas") indefinidamente aunque el audio saliente real hubiera vuelto
a ser silencio, sin que `toggleIntercom()` se volviera a llamar nunca para reenganchar el
micrófono real al nuevo sender. Además dejaba el micrófono del navegador "en uso" (icono del SO)
sin ningún uso real. **Corregido**: centralizado el reset en `_teardownConnectionObjects()` — para
el stream real, resetea `intercomActive` y el botón a estado "apagado" en CUALQUIER teardown
(voluntario o por reconexión); un reconecto exitoso posterior NO reactiva el mic solo — el
usuario tiene que volver a pulsar, igual que la primera vez (decisión explícita: comportamiento
visible y predecible, no un intento de auto-reactivación silenciosa que añadiría otra carrera).
**Checklist de verificación real** (el que el líder pidió específicamente, con log serie del P4):
abrir sesión real desde la card, activar el mic, hablar cerca del micrófono, confirmar en el log
serie del P4 que llegan bytes reales por el backchannel — y además, provocar una reconexión con
el mic activo (p. ej. cortar WiFi un instante) y confirmar que el botón vuelve a icono
apagado/gris en vez de quedarse en rojo mintiendo.

**3. Flash breve de "Error" en carga fría del dashboard, antes de asentarse en el estado
correcto.** Causa real: `startNativeSession()` trataba la ausencia momentánea de
`this._hass.connection` como error TERMINAL (badge a "Error" + `return` inmediato, sin ningún
reintento — a diferencia de cualquier otro fallo de esa función, que sí cae en el `catch` y puede
reconectar vía `_scheduleReconnect()`). En una carga en frío, HA puede insertar el elemento en el
DOM (disparando `connectedCallback()`→`startWebRTC()`→aquí) antes de que el setter `hass` se haya
invocado con una instancia ya hidratada — una carrera de arranque real, no un fallo de red. El
elemento se reinserta poco después (HA puede mover/remontar cards durante la hidratación inicial
de una vista), lo que vuelve a disparar `connectedCallback()` con `hass` ya listo — de ahí que
pareciera "asentarse solo": no se corregía nada, un segundo intento con mejor suerte tapaba el
primero. **Corregido**: reintento en silencio (sin tocar el badge, que ya muestra "Conectando..."
desde el HTML inicial) cada 250ms hasta 20 veces (~5s) antes de rendirse de verdad y mostrar
"Error". **Checklist de verificación real**: recarga completa de la página (F5/Ctrl+R, no solo
cambiar de pestaña ni navegar dentro de HA) varias veces seguidas, confirmando que el badge nunca
pasa por "❌ Error" antes de "🟢 Conectando..."/"🟢 En directo".

Nada commiteado (los tres repos siguen con cambios sin commitear a la espera de autorización
explícita, como el resto de esta sesión).

---

## 🟢 Q22-bis — Lenguaje visual del mockup Figma en la card + retirada completa del modo `go2rtc` legacy (2026-07-10)

Dos encargos del líder, atendidos en la misma pasada sobre `islautopia-intercom-card` (ambos
tocaban `render()`/`injectStyles()`, así que combinarlos evitó reescribir esas funciones dos
veces).

**1. Lenguaje visual alineado con el mockup real de Figma** (referencia:
`mockup_reconstruction.html` en el scratchpad, reconstrucción fiel del `MainView` de
`android_app`/`ios_app` — extraído `--lime #78C800`, `--cyan #00C4D4`, `--blue #1976D2`,
`--surf1/2/3`, `--muted`/`--dim`, y el layout del HUD superpuesto directamente de ese fichero).
Aplicado lo que sí tiene sentido en una card de HA:

- Paleta exacta, escopada como custom properties `--ig-*` en `.intercom-container` (nunca en
  `:root` — esta card no usa Shadow DOM, así que `:root` filtraría al documento entero de HA y
  podría chocar con otras cards custom).
- Marco de vídeo (`.feed-wrap`) con esquinas redondeadas ~22px + HUD superpuesto DENTRO del
  propio vídeo: `.live-tag` (punto de color + texto, sustituye al `.status-badge` suelto de
  antes — pulsa en rojo solo en `live`/`open`, color por estado vía `data-state`), `.audio-pill`
  cian (solo con el mic activo), `.motion-pill` ámbar (solo con `motion_entity` configurada y en
  `on` — **nunca visible con el mic activo**, regla explícita confirmada por el líder, aplicada
  en `_updateMotionPill()` y reforzada en cada punto donde `intercomActive` cambia).
- Botones de acción asimétricos: mic 76px protagonista con anillo de pulso (`.pulsering`, visible
  solo con `.active-intercom` vía CSS puro, sin JS adicional) vs. puerta 56px secundario.
- Línea de estado nueva bajo el vídeo (`.status-line`, DISTINTA del `.live-tag` — ese es el
  estado de CONEXIÓN, esta es el estado de la PUERTA): cuenta atrás real en verde
  ("Puerta abierta · Cerrando en Ns", segundo a segundo vía `_startDoorCountdown()`) al abrir, gris
  "Sistema operativo" en reposo — aplicado tanto al camino nativo (`open_result` real) como al
  camino `unlock_entity` clásico (ahí es optimista, no hay confirmación equivalente a
  `open_result` para una entidad HA arbitraria, mismo comportamiento fire-and-forget que ya tenía
  antes el botón).
- Chips de modo (`.mode-row`, **opcional**, nueva config `mode_entity` — cualquier `select.*`)
  con icono+color por modo (`MODE_META`), tocar un chip llama a
  `select.select_option`. El matching de la etiqueta real de HA a un modo conocido
  (normal/ausente/noche/custom) es por *substring* case-insensitive (`_modeKeyFor()`) —
  deliberadamente tolerante porque el string EXACTO que publicará firmware_cloud para la entidad
  de modo no estaba cerrado en el momento de este cambio (ver Fase de "Modo se arregla" en la
  auditoría HASS); una opción no reconocida se pinta igual (chip genérico sin tintar), nunca
  oculta la fila entera. Segunda config opcional nueva: `motion_entity` (`binary_sensor.*`) para
  el chip de movimiento.
- **Deliberadamente NO copiado del mockup** (ya acordado con el líder, no es una omisión):
  selector de dispositivo con desplegable (una card = un dispositivo siempre), cabecera de
  branding con logo+campana de notificaciones (HA ya tiene su propia navegación, sería
  redundante), fila de accesos rápidos a Grabaciones/Ajustes como "pantallas" (la card no navega
  a pantallas propias como una app).

**2. Modo `go2rtc`/`gateway` legacy RETIRADO POR COMPLETO** de `islautopia-intercom-card`
(decisión explícita del usuario — el proyecto habla WebRTC nativo directo, nunca go2rtc).
**Es un cambio incompatible**: cualquier instalación real que siguiera usando `stream:`/
`go2rtc_url:` en vez de `device_id:` deja de funcionar con esta versión (señalado explícitamente
en el `README.md` de la card con una nota de "Breaking change", recomendando fijar una versión
anterior si alguien dependía de ese modo). Eliminado del JS: `this.mode` (nativo es ahora el
único modo posible), `connectGo2RTCWebSocket()`, `this.vlcWS`, los inputs `stream`/`go2rtc_url`
del editor visual Lovelace, las claves de idioma `ed_stream`/`ed_url` de los 9 idiomas.
`setConfig()` exige `device_id` directamente. De paso, se aprovechó el mismo bloque para dejar de
tragar en silencio un fallo de `getUserMedia()` en `toggleIntercom()` (antes no dejaba ningún
rastro ni en consola; ahora hay un `console.warn` explícito).

**Verificación realizada sin acceso a un navegador/HA real** (mismo límite ya documentado en
Q19/Q22): `node --check` tras cada edición (sintaxis limpia) + lectura/razonamiento estructurado
del código y del CSS. **Pendiente de confirmación visual real por el líder/usuario** — checklist:

1. Cargar la card con un `device_id` real y confirmar que el marco de vídeo tiene esquinas
   redondeadas, el HUD (EN VIVO + volumen arriba, audio/movimiento abajo) queda DENTRO del vídeo
   (no como una barra aparte), y los colores coinciden con el mockup (verde lima, cian, azul).
2. Configurar `mode_entity` apuntando a la entidad de modo real del doorbell (en cuanto
   firmware_cloud la tenga lista) y confirmar que los 4 chips aparecen con su icono/color propio,
   que el chip activo coincide con el estado real, y que tocar un chip distinto cambia el modo de
   verdad.
3. Configurar `motion_entity` apuntando a `binary_sensor` de presencia y confirmar que el chip
   ámbar "Movimiento detectado" aparece solo cuando está en `on`, Y que desaparece de inmediato si
   se activa el micrófono mientras está visible (la regla de exclusión mutua).
4. Activar el micrófono y confirmar el botón grande (76px) con el halo cian/azul y el anillo de
   pulso animado; confirmar que el botón de puerta (56px) es visiblemente más pequeño en todo
   momento, no solo cuando está activo.
5. Abrir la puerta (con y sin `unlock_entity` configurado) y confirmar la cuenta atrás real
   ("Puerta abierta · Cerrando en Ns") bajo el vídeo, decreciendo cada segundo hasta volver a
   "Sistema operativo".
6. Confirmar que una instalación con `stream:`/`go2rtc_url:` (si queda alguna real) deja de
   cargar vídeo con la nueva versión — comportamiento esperado tras el breaking change, no un bug.

Nada commiteado.

---

## 🟢 Q22-ter — Pasada de precisión con valores exactos del código fuente (mismo día, tras Q22-bis)

El líder confirmó que ya no trabaja solo con capturas/reconstrucción del mockup — tiene el código
fuente real de `android_app`/`ios_app` y pasó valores exactos. Ajustado sobre lo ya construido en
Q22-bis:

- Botones: 76px/56px (aproximados) → **80px/60px exactos**.
- Paleta completada: `--ig-bg #070D1A` (antes un negro aproximado `#05070c`), `--ig-text #E8F0FE`
  (antes `#fff` plano en el texto del HUD), más `--ig-faint`/`--ig-blue-dark` definidos y
  disponibles aunque sin un hueco de uso natural todavía en el diseño actual de la card (no
  forzados a un sitio artificial).
- **Añadidas dos piezas del HUD que faltaban por completo** en la primera pasada: reloj arriba-dcha
  (hora:minuto + fecha, mono, actualizado cada segundo con la hora del propio navegador) y barras
  de señal abajo-dcha — estas últimas **adaptadas, no copiadas literalmente**: el mockup las usa
  para RSSI WiFi del dispositivo, un dato que esta card no puede conocer (no hay entidad HA para
  ello); en su lugar reflejan el estado real de la conexión WebRTC (mismo `data-state` que ya
  pinta el punto de "EN VIVO"). El control de volumen (funcionalidad real sin equivalente en el
  mockup) se reubicó junto a las barras de señal en vez de invadir el hueco exacto de la píldora
  "Audio activo".

Verificación: igual que siempre en esta sesión, `node --check` tras cada edición, sin navegador/HA
real disponible — añadir a la lista de comprobación de Q22-bis: confirmar reloj visible y
correcto arriba-dcha del vídeo, barras de señal abajo-dcha reaccionando al estado real de
conexión (todas encendidas en vivo, parciales conectando, primera en rojo si error), y que los
botones mic/puerta miden 80px/60px de verdad (no solo "se ven" distintos).

Nada commiteado.

---

## 🟢 Q23 — "Error" persistente en la card "IG DoorBell p4 v2" — bug real encontrado y CORREGIDO (no solo "probablemente un dispositivo antiguo")

El líder verificó visualmente el lote de Q22-bis/ter en real ("IG DoorBell P4" se ve bien,
"Conectando..." correcto, sin flash de error) y reportó que una SEGUNDA card ("IG DoorBell p4
v2") se queda en "Error" persistente — su sospecha inicial: apunta a un dispositivo de pruebas
antiguo/desactivado, pidió confirmarlo si era posible sin acceso a HA real.

**No pude confirmar si ESE dispositivo concreto está descontinuado** (eso vive en la lista de
dispositivos emparejados de la integración `islautopia_doorbell`, fuera de mi alcance sin acceso
a HA real) — pero SÍ encontré, leyendo el código con ese síntoma exacto en mente, un bug real que
explica perfectamente un "Error" que NO se autorrecupera nunca, y lo corregí:

`startNativeSession()` tenía DOS puntos de fallo que dejaban la card en "Error" para siempre, sin
ningún reintento — el único sitio de todo el fichero con ese comportamiento. Todos los demás
fallos (`nativeWS.onclose`, `'sessions_full'`, `connectionState` `failed`/`disconnected`, el
vigilante de 20s, `bye` recibido) sí llaman a `_scheduleReconnect()`, directamente o cubiertos por
el vigilante de vida ya en marcha. Estos dos podían dispararse ANTES de que el vigilante de vida
arrancara, así que no tenían ninguna red de seguridad:

1. `hass.connection` sigue sin aparecer tras ~5s de reintento silencioso.
2. El `catch` que envuelve `get_connection_info`/`buildNativePeerConnection()`/señalización —
   cubre exactamente el caso sospechado: si `get_connection_info` falla porque ese `device_id` ya
   no tiene una entrada válida/emparejada en la integración (coherente con un dispositivo
   antiguo/desactivado), o si `startRelaySignaling()` rechaza (relay no abre la conexión,
   dispositivo no autorizado), la card se quedaba en "Error" para siempre.

**Corregido**: ambos ahora también llaman a `_scheduleReconnect()` tras mostrar el error momentáneo,
igual que el resto del fichero. Si "IG DoorBell p4 v2" es en efecto un dispositivo descontinuado,
la card ahora debería quedarse reintentando en bucle visible ("Conectando...") en vez de un
"Error" fijo — comportamiento correcto tanto si el dispositivo vuelve como si no, y consistente
con la decisión ya tomada en Q19 (nunca dejar la card muerta sin reintentar, es un producto de
seguridad doméstica).

**Verificación pendiente por el líder/usuario**: recargar "IG DoorBell p4 v2" y confirmar que
ahora alterna a "Conectando..." con reintentos visibles (backoff 2s/4s/8s/15s) en vez de quedarse
fijo en "Error" — y, por separado, confirmar en el panel de la integración si ese `device_id` es
en efecto un dispositivo de pruebas ya descontinuado (en cuyo caso lo correcto sería
desemparejarlo/borrar esa card, no dejarla reintentando indefinidamente contra un dispositivo que
nunca va a volver).

Verificado con `node --check`, sin acceso a navegador/HA real. Nada commiteado.

---

## Estado de trabajo pendiente sin confirmación explícita (2026-07-10, "avanzar hasta donde podáis")

El usuario está fuera un par de horas y pidió avanzar sin esperar más confirmaciones para trabajo
de bajo riesgo. Repaso de los tres frentes que el líder mencionó:

1. **Retirada de go2rtc**: completa (Q22-bis) — nada pendiente.
2. **Continuidad visual con el mockup**: sustancialmente completa (Q22-bis/ter) — repasado de
   nuevo el mockup elemento por elemento; lo único que falta del mockup es la "quality-pill"
   (selector HD/resolución superpuesto al vídeo) y no se ha añadido a propósito: el mensaje de
   señalización `"quality"` que la controlaría (§5 punto 7 de `API_CONTRACT.md`, "Degradación
   adaptativa de calidad") está diseñado pero **no implementado todavía en firmware** — añadir un
   selector decorativo sin nada real detrás sería una UI engañosa. Se retoma en cuanto ese
   mensaje exista en el dispositivo.
3. **Lista de respuestas automáticas con etiquetas reales**: sigue siendo 100% trabajo de
   firmware (Q21, discovery MQTT dinámica por slot) — nada que construir en la card/integración
   hasta que el firmware publique esas entidades `button` nuevas; en cuanto lo haga, aparecerán
   solas en el dispositivo fusionado sin tocar código (ya explicado en Q21).

No hay más trabajo de bajo riesgo identificado en este momento sobre estos tres frentes más allá
de lo ya hecho — a la espera de que el líder/usuario confirme visualmente el lote de Q22-bis/ter/
Q23, o de que firmware_cloud destape alguno de los dos huecos bloqueantes de arriba.

---

## 🟡 Q24 — Backchannel HASS→altavoz del doorbell mudo, CONFIRMADO exclusivo de la card (dashboard/apps sí funcionan) — instrumentado a fondo, causa exacta aún sin confirmar

El usuario confirmó de nuevo probando en real: activar el mic desde la card no lleva audio real
al altavoz del doorbell (el sentido contrario, doorbell→PC, sí suena). Dato nuevo y crítico
aportado por el líder: **el dashboard web del propio dispositivo y las apps Android/iOS SÍ tienen
audio bidireccional funcionando** — descarta cualquier problema de firmware/protocolo/backend,
es un bug real y específico del JS de esta card.

**Investigación pedida explícitamente: comparar línea a línea la implementación de la card contra
la del dashboard (que sí funciona), no solo confirmar que "el patrón es el mismo".** Hecho, con
tres diferencias estructurales reales encontradas y descartadas cada una por razonamiento contra
la especificación WebRTC (no solo "se parece"):

1. **`pc.addTransceiver(dummyTrack, {direction:'sendrecv'})` (card) vs `pc.addTrack(dummyTrack)`
   (dashboard).** Repasado el algoritmo exacto de `addTrack()` de la spec: sin ningún transceiver
   reutilizable del mismo kind (caso real aquí, solo existe uno de vídeo), `addTrack()` crea
   internamente un transceiver nuevo con `direction:'sendrecv'` — mismo resultado exacto que la
   llamada explícita de la card. Descartado.
2. **La card siempre pasa `iceServers` (STUN + intento de TURN vía la integración); el dashboard
   usa `new RTCPeerConnection()` sin ningún ICE server.** Descartado por una razón concreta: el
   sentido INBOUND (doorbell→PC) ya funciona en la card, sobre el MISMO contexto DTLS-SRTP/par de
   candidatos que llevaría el sentido saliente — si el transporte tuviera cualquier problema
   (p.ej. un relay TURN con algún fallo direccional), el inbound tampoco funcionaría. Que RX
   funcione prueba que el transporte está sano; la causa tiene que estar en QUÉ se envía, no en
   cómo viaja.
3. **Negociación SDP** (`setRemoteDescription`→`createAnswer`→`setLocalDescription`→enviar
   respuesta): idéntica carácter por carácter entre card y dashboard.

**Hipótesis más fuerte tras descartar las tres de arriba** (no confirmada, es la única que encaja
con "RX funciona, TX no, sin ninguna excepción visible"): que la dirección NEGOCIADA
(`currentDirection`) del transceiver de audio acabe siendo distinta de `sendrecv` pese a que
`direction` (lo deseado) sí sea `sendrecv` — en ese caso `replaceTrack()` no lanzaría ningún
error (solo cambia qué pista SE enviaría SI el envío estuviera activo) pero el navegador
literalmente no transmitiría ningún paquete RTP de audio saliente. Por especificación esto no
debería depender de cómo se creó el transceiver (el cálculo de la respuesta es `direction` local
× dirección ofrecida, punto 1 ya descartado) — pero sobrevive como la única hipótesis compatible
con todo lo demás descartado.

**Instrumentado a fondo** (`dist/islautopia-intercom-card.js`, todo con el prefijo `DIAG audio`
para filtrar fácil en consola), dado que no hay acceso a navegador/HA real en esta sesión para
confirmar con datos:

- Justo tras `setLocalDescription(answer)`, ANTES de que el usuario toque el mic:
  `audioTransceiver.direction`/`currentDirection`/`mid` + la línea `m=audio` real de la SDP de
  respuesta generada.
- Al pulsar el botón de mic: éxito/fallo de `getUserMedia` (id/label/readyState/enabled/muted del
  track real), el track del sender ANTES y DESPUÉS de `replaceTrack()`, `direction`/
  `currentDirection` en ese momento, y `sender.getParameters().encodings` (por si
  `encodings[0].active:false` estuviera bloqueando el envío pese a todo lo demás — gotcha real y
  barato de comprobar).
- **Nuevo `_startAudioSendDiagnostics()`/`_stopAudioSendDiagnostics()`**: sondeo cada 3s de
  `outbound-rtp` (`bytesSent`/`packetsSent`) del sender de audio mientras el mic está activo —
  la prueba DEFINITIVA de si el navegador está enviando bytes reales o no, independiente de si
  todo lo anterior "pareció" tener éxito. Parado también en `_teardownConnectionObjects()` para
  no dejarlo huérfano tras una reconexión.

**Qué buscar en la prueba real con Playwright (dispositivo de audio falso + captura de consola)**:
1. Si `currentDirection` en el primer log (tras la oferta, antes de tocar nada) ya NO es
   `sendrecv` → el bug está en la negociación SDP.
2. Si "getUserMedia OK" nunca aparece (o aparece un `console.warn` de fallo) → problema de
   permiso/contexto del navegador para el ORIGEN DE HA (no el del doorbell) — dato nuevo:
   la card corre en el origen de Home Assistant, no en el del propio dispositivo como el
   dashboard, así que el permiso de micrófono del navegador es POR SEPARADO para cada uno; el
   usuario pudo conceder el permiso alguna vez para el dashboard/apps pero nunca para el origen
   exacto de su HA.
3. Si "replaceTrack OK" aparece pero `bytesSent` nunca sube → confirma pista correcta pero sin
   transmisión real, apunta de vuelta a `currentDirection`/`encodings[0].active`.
4. Si `bytesSent` SÍ sube de forma constante → el navegador SÍ envía audio real — contradiría lo
   ya confirmado y habría que revisar de nuevo el lado relay/firmware con este dato en la mano.

Verificado con `node --check`. Nada commiteado. **Pendiente de que el líder ejecute la prueba con
Playwright y comparta qué logs `DIAG audio` aparecen** — con eso la causa exacta debería quedar
localizada sin más rondas de especulación.

---

## 🟢 Q24-bis — Causa CONFIRMADA con datos reales (Playwright) y CORREGIDA: `addTransceiver()` explícito no negociaba `sendrecv` de verdad, pese a leerse como tal

El líder ejecutó la prueba con Playwright (dispositivo de audio falso, mic auto-concedido, sesión
real) pedida en Q24 y capturó el dato definitivo:

```
[DIAG audio] tras setLocalDescription(answer): audioTransceiver.direction=sendrecv currentDirection=null mid=null sender.track=2a83b56a-...
[DIAG audio] SDP de la respuesta (linea m=audio + primer atributo de direccion encontrado): m=audio 9 UDP/TLS/RTP/SAVPF 8 | a=recvonly
```

**La propia respuesta SDP que genera esta card decía `a=recvonly` en la línea de audio**, pese a
que `audioTransceiver.direction` se leía como `sendrecv` en ese mismo instante — el dispositivo,
como offerer, nunca esperaba ni aceptaba audio del navegador, y `replaceTrack()` posterior no
podía arreglar esto sin una renegociación real (que este diseño evita a propósito).

**Repasado el ORDEN exacto pedido por el líder**: en `buildNativePeerConnection()`, la pista muda
y `direction:'sendrecv'` se fijan en la llamada a `addTransceiver()`, que ocurre de forma síncrona
justo después del único `await` de la función (credenciales TURN) — mucho ANTES de que
`createAnswer()`/`setLocalDescription()` se lleguen a llamar (eso pasa después, al llegar la
oferta, en `handleNativeSignal`). El orden en sí NO era el problema, contra lo que parecía más
probable a priori.

**Causa real, aislada por comparación exhaustiva contra el dashboard** (mismo orden de creación
en ambos: vídeo primero vía `addTransceiver('video',...)`, audio después) — la ÚNICA diferencia
de código que quedaba sin explicar tras descartar todo lo demás en Q24: la card usaba
`pc.addTransceiver(dummyTrack, {direction:'sendrecv'})` explícito; el dashboard (que sí funciona)
usa `pc.addTrack(dummyTrack)`. Por especificación WebRTC ambas vías deberían ser estrictamente
equivalentes (cuando no hay ningún transceiver reutilizable del mismo kind, `addTrack()` crea
internamente un transceiver nuevo con `direction:'sendrecv'`, igual que el `addTransceiver()`
explícito) — la teoría decía que no debería importar, los datos reales de Playwright dijeron que
sí importa. **Corregido**: la card ahora usa `pc.addTrack(dummyTrack)` igual que el dashboard
(vía ya probada en producción), recuperando el transceiver resultante con
`pc.getTransceivers().find(t => t.sender === audioSender)` para mantener el resto del código
(`this.audioTransceiver.sender`, diagnósticos) sin cambios. Log de diagnóstico añadido justo en
la creación, para confirmar en el próximo test que `direction` sale correcto desde el origen.

Nota honesta: no tengo una explicación definitiva de POR QUÉ divergen en la práctica pese a ser
teóricamente equivalentes por especificación — puede ser un matiz real de la implementación de
Chromium entre las dos rutas de entrada a la API que no está descrito con precisión en el texto
de la spec, o alguna interacción con el resto de la config de esta card (TURN/iceServers) que no
se ha aislado del todo. Se documenta como "corregido con evidencia empírica real", no como
"entendido a fondo" — si reaparece, valdría la pena capturar el `RTCPeerConnection` completo con
`chrome://webrtc-internals` en una sesión real para profundizar.

**Verificación pedida al líder**: repetir la misma prueba con Playwright y confirmar que ahora la
línea `m=audio` de la respuesta dice `a=sendrecv` (no `a=recvonly`), que `bytesSent` en el sondeo
de `outbound-rtp` sube de forma constante mientras el mic está activo, y — la prueba real
definitiva — que el propio dispositivo recibe y reproduce audio real por el altavoz.

Verificado con `node --check`. Nada commiteado.

---

## 🟡 Q24-ter — Verificación real, dos de tres puntos CERRADOS — negociación SDP confirmada corregida; entrega de audio end-to-end pendiente de un entorno HTTPS genuino

El líder repitió la prueba con Playwright contra el HA real, dos rondas:

**CONFIRMADO a nivel de negociación SDP** (el fix de Q24-bis funciona de verdad):
`currentDirection=sendrecv` (antes `null`/desajuste) y la línea de la respuesta dice
`a=sendrecv` (antes `a=recvonly`). El cambio `addTransceiver()`→`addTrack()` corrige
genuinamente el problema de negociación que se había aislado.

**NO se pudo completar la verificación de `bytesSent`/audio real** — motivo real, no evasiva: el
entorno de prueba del líder accede a HA por `http://192.168.42.138:8123` (IP LAN plana), que el
navegador NO trata como "contexto seguro" — `navigator.mediaDevices` es directamente `undefined`
ahí, así que `getUserMedia()` falla con un `TypeError` antes de llegar a crear ningún track real,
**independientemente del fix**. Confirmado con un chequeo aislado (`isSecureContext:false`,
`hasMediaDevices:false`). Se intentó forzar `--unsafely-treat-insecure-origin-as-secure` en el
Chromium de Playwright para simular lo que vería un usuario real por HTTPS, sin efecto en ese
build empaquetado. El líder confirma que esto es una limitación del propio sandbox de pruebas, no
un hallazgo de producto — los usuarios reales entran por Nabu Casa/HTTPS o por la app, ambos
contextos seguros donde `getUserMedia()` sí debería funcionar.

**Estado final honesto de este hueco**: negociación SDP (la causa raíz real, confirmada y
corregida con datos empíricos en Q24-bis) — CERRADA. Entrega de audio end-to-end
(`bytesSent` subiendo de verdad + audio audible en el altavoz del dispositivo) — **pendiente de
un entorno con TLS real** (Nabu Casa genuino, o cualquier otro harness con HTTPS de verdad); no
se da por cerrado del todo hasta esa confirmación. Yo tampoco tengo forma de cerrarlo desde esta
sesión — cero acceso a navegador (ni siquiera el Playwright que sí tiene el líder), así que esta
última pieza queda fuera de mi alcance salvo que aparezca algún otro harness HTTPS disponible.

Nada commiteado.

---

## 🟡 Q25 — `mqtt_dispatch.py` descartaba el nuevo `action:"close"` del firmware — bug real CORREGIDO, pendiente de verificación en real

El líder de firmware, investigando un reporte real ("la luz se enciende pero nunca se apaga
sola"), corrigió `main/hardtask.c::open_door()` (rama `feature-device-auth-provisioning`): en
modo `door_m=1` (Home Assistant), el dispositivo solo publicaba `{"action":"open",...}` en
`videoportero/door/action` y nunca un cierre simétrico tras `dur` segundos, a diferencia del relé
físico (`door_m=0`, que sí lo respeta desde siempre). Corregido en firmware: ahora publica también
`{"action":"close","entity_id":"<mismo ha_e>"}` transcurridos `open_duration_s` segundos —
verificado en real por el líder con una captura MQTT en vivo (el "close" sale exactamente
`dur + 0.001s` después del "open", consistente).

**El hueco real, en `islautopia-doorbell-integration`**: `_async_dispatch()` en
`mqtt_dispatch.py` descartaba CUALQUIER `action != "open"` sin más (log a DEBUG, "Ignorando
mensaje..."). El "close" nuevo caía justo ahí. Confirmado en real por el líder con `light.faro`
(zigbee2mqtt) como `ha_e` de prueba: el "open" disparaba `light.turn_on` correctamente (visto
`zigbee2mqtt/Faro/set {"state":"ON"}` publicado por HA en el mismo instante), pero el "close" tres
segundos después no producía ningún efecto — la luz se quedaba encendida para siempre. Bug real de
producción, no un caso hipotético.

**Corregido**, siguiendo la propuesta del propio líder (aplicada tal cual, con revisión propia):

- `const.py`: nueva tabla `DOMAIN_CLOSE_SERVICE` paralela a `DOMAIN_OPEN_SERVICE` — `lock`→
  `lock.lock`, `cover`→`cover.close_cover`, `light`→`light.turn_off`, `switch`→`switch.turn_off`,
  `input_boolean`→`input_boolean.turn_off`. Deliberadamente sin `button`/`scene`/`script` (ninguno
  tiene un "cierre" con sentido real).
- `mqtt_dispatch.py`: `_async_dispatch()` ahora ramifica por `action in ("open","close")` usando
  `DOMAIN_OPEN_SERVICE`/`DOMAIN_CLOSE_SERVICE` según corresponda. Un "close" en un dominio sin
  mapeo (button/scene/script) sale sin efecto con un log a DEBUG, sin el warning ruidoso que sí
  tiene sentido para un "open" sin mapeo (ahí sí es un hueco real a rellenar).

Verificado con `python -m py_compile` (sin `homeassistant` instalable en este entorno, mismo
límite del resto de esta sesión) + una simulación aislada en Python de la tabla de resolución
open/close para los 8 dominios relevantes — confirmado que cada combinación resuelve exactamente
al servicio esperado (incluyendo que button/scene/script devuelven "sin acción" para close, sin
lanzar nada, y que un dominio desconocido cae al fallback solo en "open"). `manifest.json`
`0.2.0`→`0.3.0`. **No probado contra hardware/HA reales en esta sesión** — pendiente de que el
líder repita su captura MQTT en vivo con la integración actualizada desplegada.

Nada commiteado.

---

## 🟢 Q24-quater — Explicación DEFINITIVA del bug de Q24-bis, con la spec delante (auditoría 2026-07-12) — cierra la nota de "corregido pero no entendido a fondo"

Auditoría independiente (agente `hass_auditor`) del canal de audio de bajada de la card,
partiendo de la sospecha del coordinador de que la card pudiera estar usando el patrón incorrecto
(`addTrack` tardío al pulsar el mic → renegociación SDP que el P4 no soporta). **Verificado con
el código delante: esa sospecha NO aplica** — la card ya implementa el patrón correcto (pista
muda de un `AudioContext` añadida en `buildNativePeerConnection()`, ANTES de la negociación;
`toggleIntercom()` solo hace `getUserMedia` + `replaceTrack()`, nunca `addTrack`/renegociación),
idéntico al dashboard web del firmware. El bug real era el ya aislado y corregido en Q24-bis
(`addTransceiver()` explícito → `addTrack()`), pendiente solo de verificación end-to-end (Q24-ter).

**Lo nuevo de esta auditoría: la explicación de POR QUÉ divergen, que Q24-bis dejó como "matiz
de Chromium no descrito con precisión en la spec" — no lo es; es comportamiento especificado**:

- **RFC 9429 (JSEP) §5.10** + pasos de `setRemoteDescription()` de webrtc-pc: al aplicar una
  **oferta remota** (y el doorbell es SIEMPRE el offerer — ICE-Lite, nunca procesa ofertas), cada
  m-line entrante solo puede asociarse con un transceiver local existente **si ese transceiver
  fue creado por `addTrack()`** — los creados con `addTransceiver()` están excluidos de ese
  matching a propósito (solo se asocian cuando el lado local genera la oferta, que aquí no pasa
  nunca).
- Consecuencia exacta en la versión antigua: el transceiver explícito de audio quedaba huérfano
  para siempre — **coincide dato a dato con el diagnóstico Playwright de Q24-bis**
  (`direction=sendrecv` pero `mid=null`, `currentDirection=null`) — y `setRemoteDescription()`
  creaba OTRO transceiver implícito para la m-line de audio, con direction por defecto
  `recvonly` → respuesta `a=recvonly` → cero RTP de audio saliente, sin ninguna excepción.
- El vídeo "funcionaba" con ambas variantes solo por coincidencia: el default del transceiver
  implícito (`recvonly`) es exactamente lo que el vídeo quiere. (Nota lateral: el comentario del
  dashboard en `webtask.c` sobre `addTransceiver('video',{direction:'recvonly'})` — "para que
  JSEP lo reutilice por orden de m-line" — es incorrecto por la misma regla, pero inofensivo por
  esa misma coincidencia.)

Comentario del código de la card actualizado con esta explicación (sustituye al texto que decía
que la spec afirmaba equivalencia — afirmaba lo contrario para este caso). También verificado en
esta auditoría, sin desajustes: el esquema de señalización de la card contra `API_CONTRACT.md`
§1.4/§3.3 (offer/answer/candidate/bye/open/open_result, `slot` devuelto en cada mensaje local,
`?token=` en SSE y POST, `request_offer` solo en remoto, candidate como cadena cruda).

**Sigue pendiente (sin cambios respecto a Q24-ter)**: la verificación end-to-end de audio real
(`bytesSent` subiendo + voz audible en el altavoz del P4) necesita un navegador en un origen HTTPS
genuino — el harness local por `http://IP:8123` no tiene `navigator.mediaDevices`. Cómo probarlo:
abrir HA vía el add-on `islautopia_ha_https` (`https://<id>.ha.doorbell.islautopia.com:8443`) o
Nabu Casa, activar el mic en la card, y mirar en consola los logs `DIAG audio` (deben mostrar
`a=sendrecv` en la respuesta y `bytesSent` creciendo cada 3s) + confirmar voz en el altavoz.
Sintaxis re-verificada (`node --check`). Nada commiteado.

---

## 🟢 Q24-quinquies — Hipótesis del usuario CONFIRMADA: el recurso Lovelace manual no tiene ningún cache-busting — hallazgo real, documentado y con fix de proceso aplicado

El usuario planteó, muy acertadamente, la explicación más probable de por qué no se podía
confirmar con certeza si el fix de Q24-bis (2026-07-11) estaba realmente sirviendo en el HA real:
aunque el fichero en `config/www/` esté corregido, el navegador puede seguir sirviendo una copia
cacheada vieja del módulo JS si la URL del recurso Lovelace nunca cambia.

**Confirmado leyendo el repo, no asumido**:
- `README.md` de `islautopia-intercom-card`, Opción B (instalación manual): el recurso se registra
  literalmente como `/local/islautopia-intercom-card.js` — **URL pelada, sin ningún sufijo de
  versión/cache-bust**. Mismo texto exacto que el log real de Q10 (`config/www/
  islautopia-intercom-card.js`, recurso `/local/islautopia-intercom-card.js`).
- Contraste real dentro del propio repo: la Opción A (HACS) SÍ tiene un paso 5 "Refresh your
  browser cache" — señal de que los propios mantenedores ya sabían del problema de caché para esa
  vía, pero nunca trasladaron ninguna mitigación equivalente a la vía manual (que es la que se usa
  de verdad para desplegar cambios en desarrollo, ver Q10/Q24-ter).
- Grep en los tres repos (`ig_hassio_addons`, `islautopia-doorbell-integration`,
  `islautopia-intercom-card`) sin ningún resultado de `hacstag`/versión/cache-bust fuera de ese
  único paso de HACS — no existe ningún mecanismo de cache-busting en absoluto para el recurso
  manual, en ningún punto del proceso de instalación o actualización.
- Confirmado también por qué esto es plausible como explicación de la ambigüedad de Q24-ter: la
  prueba con Playwright del líder pudo perfectamente reutilizar un contexto/perfil de navegador ya
  usado en pruebas anteriores contra el mismo `192.168.42.138`, sirviendo el módulo cacheado de una
  carga previa — sin que nada en la consola lo delatara como tal (una carga de módulo ES desde
  caché no deja ningún rastro distintivo salvo comparar el propio contenido servido).

**Fix de proceso aplicado en el repo** (documentación + instrumentación, nada que toque el HA real
del usuario):
1. **`dist/islautopia-intercom-card.js`**: nueva constante `CARD_BUILD_ID` +
   `console.log('[islautopia-intercom-card] modulo cargado - build=...')` al cargar el módulo
   (top-level, se ejecuta siempre, incluso antes de que exista ninguna instancia de la card) — da
   una forma barata y objetiva de zanjar la duda desde las DevTools reales: si el `build` que
   aparece en consola no coincide con `CARD_BUILD_ID` del fichero en el repo, el navegador está
   sirviendo una copia cacheada vieja, sin ambigüedad. `node --check` limpio.
2. **`README.md`**: la Opción B (instalación manual) ahora recomienda registrar el recurso con
   `?v=1` (no la URL pelada) y añade un aviso explícito de cómo actualizar de forma segura: bumpear
   el `?v=` en la propia entrada de recurso de Lovelace cada vez que se sobrescribe el fichero — un
   *hard refresh* del navegador NO es fiable en todos los casos (proxies, service workers, etc.),
   cambiar la URL sí lo es siempre.

**Importante para el líder, acción real pendiente sobre el HA del usuario** (fuera de mi alcance,
recordatorio explícito): el recurso YA registrado en la instancia real (desde Q10, 2026-07-09)
sigue teniendo la URL pelada sin `?v=` — este fix de README solo aplica a instalaciones nuevas. Para
que el mecanismo de verificación (`CARD_BUILD_ID`) sirva de algo en la instancia real, hace falta
desplegar el fichero actualizado (con el log de build) Y editar la entrada de recurso existente en
`Settings > Dashboards > Resources` para añadirle `?v=1` (o el que corresponda) — solo editar el
fichero en `config/www/` sin tocar la URL del recurso no garantiza que el navegador lo recargue.

Nada commiteado en ninguno de los dos repos.
