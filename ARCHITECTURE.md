# Arquitectura — integración Home Assistant nativa para IG Doorbell

**Estado: diseño validado con el usuario (2026-07-09) — ver resoluciones Q1-Q6 en
`COORDINATION.md`. Implementación inicial en curso.**

Cambio importante sobre la primera versión de este documento: la integración Python
(`custom_components/islautopia_doorbell/`) **NO vive en este repo** — vive en un repo nuevo
dedicado, **[`islautopia-doorbell-integration`](https://github.com/Islautopia/islautopia-doorbell-integration)**
(`C:\Proyectos_espressif\islautopia-doorbell-integration`). Motivo (decisión del usuario, Q1):
una integración HACS y un add-on de Supervisor son mecanismos de distribución y ciclos de release
distintos — no mezclar con este repo, que ya tiene usuarios reales instalados con sus propios
tags (`rc0.1`..`rc1.1`). Este documento (`ig_hassio_addons`) sigue siendo el punto de referencia
del diseño conjunto de los tres repos (integración + card + futuro del addon), pero el código de
la integración en sí y su propio `CLAUDE.md` viven en el repo nuevo.

## 1. Por qué hace falta esto (resumen del encargo)

`door_mode=1` ("modo Home Assistant") del doorbell publica MQTT
(`videoportero/door/action`, payload `{"action":"open","entity_id":"<ha_e configurado en el
doorbell>"}`, ver `API_CONTRACT.md` §4) pero MQTT es pub/sub puro — sin nada escuchando ese topic
y despachando el servicio de HA correspondiente, no pasa nada. Hasta ahora la única solución era
que el usuario escribiera a mano una Automatización HA. Inaceptable para un producto comercial:
el objetivo es que **cero configuración en HA** sea necesaria más allá de instalar la
integración y emparejar el dispositivo.

Aprovechamos el mismo trabajo para cerrar el resto de huecos que la auditoría previa identificó:
el add-on actual (go2rtc + Caddy + cert autofirmado) resuelve un problema que el propio firmware
ya resuelve de fábrica (WebRTC nativo, HTTPS real, TURN propio) — motivo real de peso para una
integración nueva, no solo el despacho de MQTT.

## 2. Qué se auditó del estado actual (no repetir este trabajo)

Ver `CLAUDE.md` para el resumen. Detalle completo abajo en la sección 7 (histórico).

## 3. Decisión de alcance — qué NO hace la integración nueva

Antes de diseñar qué hace, importa fijar qué **no** hace, porque simplifica mucho el diseño:

- **No mantiene ninguna sesión administrativa persistente contra el doorbell.** `POST
  /api/pair_app` (contrato §1.5) requiere login previo (cookie de sesión), pero la credencial de
  64 hex que devuelve está pensada para uso REMOTO (`/ws/client/<id>?token=`,
  `/device/<id>/app_turn_credentials`) — no autentica llamadas REST locales como
  `/api/get_states`. Si la integración quisiera hacer polling continuo de `/api/get_states` o
  `/api/firmware_info`, necesitaría persistir la contraseña de admin (o volver a pedirla) para
  poder re-loguearse tras cada reinicio del dispositivo (las sesiones no sobreviven un
  `esp_restart()`) — justo el tipo de secreto sensible que NO queremos que la integración guarde
  si se puede evitar.
- **Consecuencia de lo anterior:** la integración usa el login+contraseña de admin **una única
  vez, de forma transitoria**, durante el flujo de emparejamiento inicial (config flow), solo
  para obtener la credencial de `pair_app` — email/contraseña se descartan inmediatamente después,
  nunca se persisten. Runtime normal no vuelve a necesitarlos.
- **No hace de proxy de medios.** La card en el navegador habla WebRTC (SSE/POST local o WS
  remoto) directamente contra el doorbell/relay — la integración Python nunca toca un paquete de
  audio/vídeo. Su papel es "credential broker" + resolución mDNS del lado servidor + despacho
  MQTT→servicio.
- **No duplica el estado que el propio firmware ya publica por MQTT discovery** (modo, timbre,
  sensor de puerta/presencia — `main/networktask.c::enviar_ha_discovery_completo()`). Esas
  entidades ya existen en HA en cuanto el usuario configura el broker en el doorbell — la
  integración nueva no las vuelve a crear.

Esto dejaría la integración con exactamente tres responsabilidades runtime:

1. **Despachar `videoportero/door/action`** al servicio de HA correcto (el encargo central).
2. **Credential broker para la card**: pairing (una vez), resolución mDNS server-side, y
   credenciales TURN efímeras vía `app_turn_credentials`.
3. **Config flow** (alta/baja de doorbells, sin YAML).

## 4. Estructura de ficheros propuesta

```
custom_components/islautopia_doorbell/
  __init__.py            # async_setup_entry/async_unload_entry, arranca el listener MQTT global
  manifest.json           # domain "islautopia_doorbell", dependencies: ["mqtt"], zeroconf config
  const.py                 # DOMAIN, topic MQTT, defaults, dominios→servicio de despacho
  config_flow.py           # UI flow (zeroconf + manual), pairing transitorio, options flow
  api.py                    # cliente HTTP fino: login, pair_app, app_turn_credentials
  mqtt_dispatch.py          # suscripción única a videoportero/door/action + resolución de servicio
  discovery.py              # helpers de resolución mDNS server-side (_igdoorbell._tcp.local.)
  websocket_api.py          # comandos WS consumidos por la card (get_connection_info, get_turn_credentials)
  diagnostics.py            # (opcional) volcado de diagnóstico sin secretos, estándar HA
  strings.json
  translations/en.json
  translations/es.json
```

Nombre de dominio: `islautopia_doorbell` (confirmado, Q1). **Implementado** en
`islautopia-doorbell-integration/custom_components/islautopia_doorbell/` — los ficheros de la
lista de arriba existen ya (`diagnostics.py` quedó fuera de la primera pasada, no bloqueante,
añadir en una iteración posterior si hace falta). Pendiente de verificar contra una instancia
real de Home Assistant (no había ninguna disponible al escribir el código) — ver el propio
`README.md`/`CLAUDE.md` de ese repo para el detalle de qué falta validar.

### 4.1 `mqtt_dispatch.py` — el corazón del encargo

- Se suscribe **una sola vez** (no por config entry) a `videoportero/door/action` vía la
  integración `mqtt` nativa de HA (`homeassistant.components.mqtt.async_subscribe`), activa
  mientras exista al menos un config entry de `islautopia_doorbell` cargado.
- Parsea el JSON `{"action":"open","entity_id":"..."}`. Si `action != "open"` o el JSON es
  inválido, descarta con un log a nivel debug (compatibilidad hacia adelante si el firmware añade
  más `action` en el futuro).
- Resuelve el dominio de `entity_id` (`entity_id.split(".")[0]`) y despacha:

  | Dominio | Servicio |
  |---|---|
  | `lock` | `lock.unlock` |
  | `cover` | `cover.open_cover` |
  | `light` | `light.turn_on` |
  | `switch` | `switch.turn_on` |
  | `button` | `button.press` |
  | (otro) | fallback: `homeassistant.turn_on` (genérico, cubre varios dominios más) + `LOGGER.warning` con el dominio no contemplado explícitamente, para que el hueco sea visible en vez de silencioso |

- No necesita desambiguar de qué doorbell vino el mensaje — el `entity_id` ya viaja en el
  payload y es autosuficiente. Esto es justo lo que evita que nos afecte la limitación de topics
  planos sin `device_id` que tiene el resto de la publicación MQTT del firmware (ver
  `CLAUDE.md`).
- Si `hass.states.get(entity_id)` es `None` (entidad no existe/fue borrada), log de warning
  claro en vez de una excepción silenciosa — ayuda mucho a diagnosticar un `ha_e` mal escrito en
  el propio doorbell.

### 4.2 `config_flow.py`

- **Paso de descubrimiento** (`async_step_zeroconf`): HA ya tiene soporte nativo de Zeroconf: si
  detecta un servicio `_igdoorbell._tcp.local.` (el mismo que ya usa la app, contrato §0-bis),
  dispara este flujo automáticamente y pre-rellena `device_id`/`name` desde los TXT records. El
  usuario solo confirma y pasa a emparejar.
- **Paso manual** (`async_step_user`): si no hay descubrimiento (red sin mDNS, o el usuario
  prefiere ir directo), pide la IP/host local. Llama a `GET /api/device_id` (sin sesión, existe
  exactamente para este primer contacto, contrato §0) para confirmar que hay un doorbell real ahí
  y obtener su `device_id` real.
- **Paso de emparejamiento** (`async_step_pair`): pide email + contraseña de administrador
  (las que el usuario ya creó en `/api/setup` desde la app/dashboard). Hace, en este orden:
  1. `POST /api/login` (obtiene cookie de sesión, transitoria — no persistida)
  2. `POST /api/pair_app?label=Home+Assistant` (obtiene la credencial de 64 hex)
  3. `POST /api/logout` (best-effort, libera el slot de sesión del doorbell — solo hay 8
     concurrentes)
  4. Descarta email/contraseña de memoria inmediatamente
- **Resultado**: crea el config entry con `{device_id, host_hint, credential}` en `entry.data`
  (HA cifra/protege el almacenamiento de config entries con su propio mecanismo — es el
  "almacenamiento nativo de HA para credenciales" al que se refiere el encargo; no hace falta
  inventar cifrado propio).
- **Options flow**: permite re-emparejar (si la credencial fue revocada desde el panel de admin
  de la nube) o cambiar el hint de host manual.
- Errores a manejar explícitamente (mapeo directo del contrato): `302` a `/login?error=1` →
  "credenciales inválidas"; `409 device_not_paired` de `pair_app` → mensaje claro ("el propio
  doorbell aún no está emparejado con la nube, espera a que termine su registro"); `502
  cloud_authorize_failed` → "la nube no acepta el registro, reintenta más tarde".

### 4.3 `websocket_api.py` — el puente hacia la card

Comandos registrados con `websocket_api.async_register_command`, consumibles desde
`hass.connection.sendMessagePromise(...)` en la card (mismo origen, autenticado como cualquier
otro comando WS de HA — no hace falta ningún token nuevo, la propia sesión de usuario de HA ya
autoriza):

- `islautopia_doorbell/get_connection_info` `{device_id}` → `{device_id, relay_ws_url,
  credential}`. Ya **no** incluye ningún dato de resolución LAN — ver más abajo por qué se quitó
  por completo (2026-07-10), no solo se dejó sin usar.
- `islautopia_doorbell/get_turn_credentials` `{device_id}` → llama en caliente a `GET
  /device/<id>/app_turn_credentials` (contrato §3.1-bis) con la credencial persistida, y
  reenvía la respuesta tal cual a la card (TTL 3600s — se pide fresca cada vez que la card
  arranca una sesión nueva, no se cachea del lado integración).
- La credencial de `pair_app` en sí (necesaria para el `?token=` del WS remoto,
  `wss://relay.../ws/client/<device_id>?token=<credencial>`) **sí viaja a la card** en
  `get_connection_info` — no hay forma de evitarlo del todo: es la propia card (JS en el
  navegador) quien abre esa conexión WS directamente. Es el mismo nivel de exposición que
  cualquier otro secreto de una integración mostrado a un usuario ya autenticado en el frontend
  de HA (p. ej. tokens de larga duración en el propio perfil de HA) — no un secreto nuevo tipo
  "nunca debe verlo el navegador".

**Implementado.** Historial completo del campo `local_host` que ya no existe, por si alguien se
pregunta por qué falta (mismo tipo de contexto que ya se documentó para el resto de decisiones):
al escribir la card se descubrió (`COORDINATION.md` Q7) que nunca usaba `local_host` para
construir su URL de conexión — el certificado real del doorbell está emitido para el
**hostname** `<device_id>.doorbell.islautopia.com`, no para ninguna IP, así que la card conecta
siempre por ese hostname. En su momento se dejó el campo en la respuesta como "informativo/
futuro". **Eliminado del todo el 2026-07-10** (`COORDINATION.md` Q15/Q16, `discovery.py`
borrado entero) tras confirmar dos cosas con el usuario: (1) ningún consumidor real lo usaba —
confirmado con grep en los tres repos, y (2) mDNS es multicast y normalmente no cruza límites de
VLAN/subred sin un relay explícito — para cualquier instalación con segmentación de red real
(el propio caso del usuario, con doorbells aprovisionados manualmente por IP en una VLAN
distinta a la de HA), apoyarse en mDNS para esto habría sido activamente incorrecto, no solo
código muerto. Además, resolver esto en vivo costaba hasta 4 segundos bloqueando cada arranque
de sesión de la card antes de arreglarse a no-bloqueante — un coste real por un valor que además
nunca debió estar en el camino de conexión. `CONF_HOST_HINT` (el hint de IP capturado al
emparejar, en `config_flow.py`) se mantiene — barato, sin coste en tiempo de ejecución, podría
servir algún día para soporte/diagnóstico manual aunque hoy no tenga consumidor activo.

### 4.3-bis Device registry — soporte del device picker nativo de la card (2026-07-09)

`__init__.py::async_setup_entry` registra cada doorbell como `Device` en el device registry de HA
(`identifiers={(DOMAIN, device_id)}`, sin entidades propias) — no aporta nada por sí solo, pero es
lo que permite que el editor de `islautopia-intercom-card` use el picker nativo `<ha-selector>`
(`selector: {device: {filter: {integration: 'islautopia_doorbell'}}}`, el mismo componente que ya
usa HA en sus propios formularios) en vez de pedirle al usuario que copie/pegue un `device_id` a
mano. El picker devuelve el ID interno del device registry de HA (una UUID opaca); el editor lo
traduce de vuelta a nuestro `device_id` propio vía ese mismo `identifiers` — la config de la card
solo guarda siempre nuestro `device_id` (estable, derivado de la MAC), nunca el ID interno de HA.
Implementado en ambos repos (backend en `islautopia-doorbell-integration`, picker en
`islautopia-intercom-card`).

## 4.4 Estado de implementación (2026-07-09)

Escrito y auto-verificado con `python -m py_compile` (sintaxis) y validación de los JSON
(`manifest.json`, `strings.json`, `translations/*.json`) — **no probado contra una instancia real
de HA** (no había ninguna disponible en esta sesión). Antes de dar la integración por terminada,
verificar con una instancia real: flujo de descubrimiento Zeroconf, emparejamiento completo
contra un doorbell real, recarga/desinstalación de la entrada, el picker `ha-selector` del editor
de la card (backend+frontend juntos), y sobre todo `discovery.py` — la API async de Zeroconf de
HA Core (`async_get_async_instance`, `AsyncServiceBrowser`) varía entre versiones de HA Core y es
el módulo con más riesgo de necesitar ajustes.

## 5. Rediseño de la card (`islautopia-intercom-card`)

Objetivo: hablar el protocolo nativo del doorbell como camino primario, sin perder los buenos
patrones de UX ya existentes (pista de audio dummy + hot-swap sin renegociar, cierre limpio al
salir de pestaña, editor visual, i18n, memoria de volumen).

- **Nuevo modo `native`** (activado por config `device_id: <id>` en vez de `stream:
  <nombre_go2rtc>`) — coexiste con el modo `go2rtc` actual (renombrado internamente, sigue
  sirviendo el caso "cualquier intercomunicador RTSP" vía el add-on, ver sección 6).
- Al montar, pide `get_connection_info`/`get_turn_credentials` a la integración vía
  `hass.connection.sendMessagePromise`.
- **Selección de transporte**: intenta primero señalización local por HTTPS real del propio
  doorbell (`GET https://<device_id>.doorbell.islautopia.com:8443/webrtc/signal` — por
  **hostname**, nunca por la IP resuelta por mDNS, ver `COORDINATION.md` Q7) con un timeout
  corto (~3s — cubre tanto "doorbell offline" como "el navegador está fuera de la LAN", p. ej.
  viendo el dashboard vía Nabu Casa remoto). Si falla/timeout, cae a
  `wss://relay.doorbell.islautopia.com/ws/client/<device_id>?token=<credencial>` +
  `request_offer`.
- **Auth de la señalización local** (`COORDINATION.md` Q9, cambio de contrato 2026-07-09): tanto
  el `GET /webrtc/signal` como el `POST /webrtc/signal/post` locales exigen ahora
  `?token=<credencial de pair_app>` como query param (mismo valor que ya se pedía para el WS
  remoto, `EventSource` no admite cabeceras propias) — sin él, `401`. Ya aplicado en la card.
- SDP: BUNDLE (`a=group:BUNDLE 0 1`), vídeo `H264` `profile-level-id=42e029` (perfil real del
  encoder, no negociable — ver nota del contrato sobre Safari/iOS), audio `PCMA/8000 sendrecv`
  únicamente. `iceServers` = STUN propio (`stun:46.225.57.138:3478`) + TURN efímero de
  `get_turn_credentials`.
- **Apertura de puerta**: camino primario = mensaje de señalización `{"type":"open"}` sobre el
  canal ya abierto (contrato §3.3, funciona igual en local SSE/POST que en remoto WS, no necesita
  ICE/DTLS completo — basta con tener `offer` recibida). Camino alternativo, configurable, se
  mantiene: `unlock_entity` + `hass.callService()` tal cual existe hoy (útil para quien prefiera
  que abrir puerta pase por una Automatización/entidad de HA con su propio logging/condiciones, o
  para el modo `go2rtc` legacy que no tiene canal de señalización nativo).
- Se conserva: pista de audio dummy sendrecv desde el arranque + `replaceTrack` al pulsar
  micrófono (sigue siendo válido — el códec PCMA/8000 lo negocia el propio SDP, el navegador
  codifica a lo que la oferta declare), cierre limpio en `disconnectedCallback`, editor visual,
  i18n, volumen en `localStorage`.

**Implementado** en `dist/islautopia-intercom-card.js` (sigue siendo un único fichero sin build
step — se mantuvo el enfoque existente, no se introdujo tooling nuevo). Sintaxis verificada con
`node --check`. **No probado contra una instancia real de HA + doorbell real** (no disponible en
esta sesión) — antes de darlo por cerrado, verificar en real: negociación SDP completa, hot-swap
de audio, fallback local→relay, y `open`/`open_result`.

## 6. El add-on Docker (`islautopia_intercom`) — deprecación activa (2026-07-09)

**Decisión del usuario, más lejos que la propuesta original de este documento**: no solo
re-etiquetar, sino deprecación **activa y visible** — banner de aviso prominente (no una nota al
pie) al principio de `README.md` y `DOCS.md` del add-on, y del `README.md` raíz del repo, dejando
claro que la vía recomendada para hardware Islautopia es
[`islautopia-doorbell-integration`](https://github.com/Islautopia/islautopia-doorbell-integration),
y que el add-on queda como modo de compatibilidad RTSP/go2rtc genérico para intercomunicadores de
terceros. **Implementado, sin romper nada funcionalmente** — usuarios reales instalados
(`rc0.1`..`rc1.1`) siguen funcionando exactamente igual. Ver `COORDINATION.md` Q4 para el detalle
completo de la resolución (incluida la duda de DuckDNS, cerrada sin acción).

Contexto histórico que motivó la propuesta original (ya superada por la decisión de arriba, se
deja como referencia): análisis de la auditoría (ver `CLAUDE.md`) identificó qué es redundante
(go2rtc, cert autofirmado, STUN de Google) frente al doorbell nativo, y qué puede seguir teniendo
valor propio (proxy HTTPS genérico para TODA la instancia HA; posicionamiento "compatible con
cualquier intercomunicador RTSP" como producto separado del hardware Islautopia). Mantener el
add-on tal cual, sin cambios funcionales, pero re-etiquetado en README/DOCS como **"modo de
compatibilidad
genérica RTSP/go2rtc"**, explícitamente distinto de la nueva integración nativa — que pasa a ser
la vía recomendada para hardware Islautopia. No romper nada para quien ya lo tiene instalado.

## 6-bis. Add-on nuevo: `islautopia_ha_https` — HTTPS transparente para toda la instancia HA (2026-07-09)

Pieza nueva, pedida explícitamente por el líder tras confirmar la Q7 de `COORDINATION.md`: el
certificado del propio doorbell asegura la conexión AL doorbell, no el origen que sirve el
dashboard de HA — `getUserMedia()` exige *secure context* del origen que carga la card, es decir
de HA, no del dispositivo remoto con el que habla. Nada de lo construido hasta ahora (integración
`islautopia_doorbell`, card en modo nativo) resuelve esto; hace falta una pieza sola con ese
trabajo, y por naturaleza (proxy TLS persistente delante de todo HA) tiene que ser un add-on de
Supervisor, no una integración Python.

**Implementado** en `islautopia_ha_https/` (mismo repo, junto al add-on legacy — a diferencia de
la integración Python, esto SÍ encaja en `ig_hassio_addons` porque es, en efecto, otro add-on
Docker/Supervisor, el mismo mecanismo de distribución que el legacy):

- `run.sh` en tres fases, cada una descrita con su propio comentario en el fichero: (1) identidad
  propia persistida en `/data` (`POST /ha_instance/register`, una sola vez); (2) detección de IP
  local vía la API del Supervisor (misma técnica que ya probó el add-on legacy) +
  `POST /ha_instance/<id>/report_ip`, revisado cada 5 min en un bucle de fondo; (3) certificado
  real vía `GET /ha_instance/<id>/cert`, comparando `hash` antes de reescribir/recargar (mismo
  patrón que `https_cert_task.c` del firmware), revisado cada ~12h para recoger renovaciones.
- Caddy como proxy (`:8443`, `reverse_proxy homeassistant:8123`, sin admin API activada —
  reinicio de Caddy por kill+relanzar en vez de `caddy reload`, para no tener que exponer esa
  superficie en un proxy que da acceso a toda la instancia).
- **Contrato del VPS ya verificado en real** (mensaje del líder 2026-07-09): `register`/
  `report_ip`/`cert` de `/ha_instance/*` probados de extremo a extremo contra
  `relay.doorbell.islautopia.com` (mismo host que ya usa el propio doorbell para `/register`),
  incluida una emisión real de certificado Let's Encrypt. El `API_BASE` en `run.sh` ya no es una
  asunción a confirmar, está verificado.
- **Documentación con estructura fija pedida por el usuario** (no dejada a criterio libre): qué
  es / para qué sirve / esquema de cómo funciona por dentro (con diagrama ASCII explícito de que
  el VPS NUNCA está en el camino de los datos reales, solo en las llamadas ocasionales de
  registro/DNS/certificado) / riesgos controlados (los 6 puntos exactos acordados, sin
  reformular) / configuración necesaria (declarada honestamente como "prácticamente cero", con el
  único paso manual real —navegar al nuevo hostname al menos una vez, el add-on no puede hacerlo
  por ti— declarado explícito en vez de implicar "cero fricción total" si no lo es).
- **Posicionamiento explícito, con tono positivo, en el propio README/DOCS**: (a) NO es
  alternativa ni competencia de Nabu Casa — no da acceso remoto bajo ningún concepto, el hostname
  público solo resuelve a la IP LOCAL; para acceso remoto real, Nabu Casa o proxy propio, sin
  solapamiento. (b) SÍ sirve también para interfonos/cámaras de terceros vía RTSP/`go2rtc` (no
  solo Islautopia) — dicho con franqueza, mismo espíritu que ya tenía el add-on legacy, en vez de
  ocultarlo (no es una exposición nueva, es evidente leyendo el esquema técnico).

**Verificado en real (2026-07-09) — éxito completo, sin bugs, sin ajustes de código necesarios.**
Desplegado y arrancado en la instancia real del usuario (`192.168.42.138`, HA 2026.6.4) por la
sesión líder (permisos que esta sesión no tiene ni debe tener, ver nota de protocolo más abajo).
Log real revisado línea por línea contra `run.sh`: identidad registrada
(`d01d1aafaaa8fcc0`), IP local reportada, certificado real emitido y aplicado, Caddy sirviendo en
`:8443` (h1/h2/h3). Detalle completo y log íntegro en `COORDINATION.md` Q10. Nota de terminología
de UI (no de código): en HA 2026.6.4 la sección de add-ons se llama "Aplicaciones", no
"Complementos".

**Nota de protocolo de esta verificación**: esta sesión (HA integration) tiene bloqueado a nivel
de sistema cualquier intento de autenticarse o escribir contra la instancia real del usuario,
incluso con credenciales explícitamente autorizadas y relayadas por la sesión líder — el
clasificador de permisos exige que la autorización aparezca de un mensaje directo del usuario en
el propio transcript de esta sesión, no relayada por otro agente, sin excepción. La sesión líder
sí tenía autorización directa y pudo ejecutar el despliegue real; esta sesión se limitó a preparar
el código, verificarlo sintácticamente, y revisar el log real después de recibirlo. Es un
comportamiento correcto y esperado del sistema, no un bug ni una limitación a "arreglar".

## 6-ter. TODO aparcado: entidad `camera` nativa vía WebRTC (2026-07-09)

Decisión explícita del usuario: aparcado, "tal vez algún día... o tal vez no" — ni construido ni
descartado. **Investigación completa ya hecha y documentada en `COORDINATION.md` (sección TODO al
final)** — no repetirla si se retoma. Resumen de una línea: la API de cámara WebRTC de HA asume
que el frontend ofrece y la cámara responde, justo lo contrario del doorbell (ICE-Lite,
solo-oferta) — la única vía realista es un puente de medios real (`aiortc`) dentro de la
integración, con HA sí en el camino del vídeo (no solo de la señalización, al contrario de la
esperanza original), esfuerzo/riesgo sustancialmente mayor que cualquier otra pieza construida
hasta ahora en este lado del proyecto.

## 7. Auditoría previa (histórico, ya hecha — no repetir)

Ver el encargo original de la sesión líder para el resumen completo (arquitectura actual del
add-on y de la card, qué es redundante, qué no). Resumen de una línea: el add-on resuelve con
go2rtc+Caddy+cert-autofirmado+STUN-de-Google un problema (RTSP→WebRTC, HTTPS para micrófono, ICE
básico) que el firmware YA resuelve de fábrica con WebRTC nativo + HTTPS Let's Encrypt real +
TURN propio; la card habla el protocolo WS propio de go2rtc, sin TURN, con apertura de puerta
solo vía `callService`. Hallazgo adicional de esta sesión (no estaba en la auditoría previa): los
topics MQTT de estado/comando del firmware (`videoportero/modo/state` etc., distintos del nuevo
`videoportero/door/action`) son planos, sin `device_id` — ver `CLAUDE.md` y `COORDINATION.md`
para el detalle y por qué no bloquea el diseño de aquí, pero sí conviene que el firmware lo sepa.
