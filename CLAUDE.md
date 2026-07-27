# Islautopia — integración Home Assistant (repo `ig_hassio_addons`)

Este repo (y sus hermanos `islautopia-intercom-card` e **`islautopia-doorbell-integration`**, ver
más abajo) son responsabilidad de la sesión "HA integration" del equipo Islautopia. El líder de
firmware trabaja en `IG_Doorbell` (`C:\Proyectos_espressif\IG_Doorbell`) — la fuente de verdad de
la interfaz del propio doorbell es **siempre**
`C:\Proyectos_espressif\IG_Doorbell\API_CONTRACT.md`. No la dupliques aquí; este repo la
referencia.

**El código de la integración Python NO vive en este repo.** Vive en un repo nuevo dedicado,
`C:\Proyectos_espressif\islautopia-doorbell-integration` (decisión del usuario, `COORDINATION.md`
Q1: HACS integration y add-on Supervisor son mecanismos de distribución distintos, no mezclar
con este repo que ya tiene usuarios reales con sus propios tags). Este repo (`ig_hassio_addons`)
sigue siendo donde vive el diseño conjunto de los tres repos y el propio add-on legacy.

Documentos de esta misión, en este repo:
- **`ARCHITECTURE.md`** — diseño concreto de la integración `custom_components` (código en el
  repo nuevo) y del rediseño de la card (código en `islautopia-intercom-card`). Léelo antes de
  tocar código.
- **`COORDINATION.md`** — preguntas con la sesión líder de firmware (Q1-Q6 ya resueltas, ver
  historial), mismo formato 🔴/🟡/🟢 que usa `IG_Doorbell_App/COORDINATION.md`.

## Qué hay hoy en este repo (estado heredado, en deprecación activa)

`islautopia_intercom/` — add-on Docker (Supervisor) que empaqueta Caddy + go2rtc, publicado en
GitHub (`Islautopia/ig_hassio_addons`), con usuarios reales instalados (tags `rc0.1`..`rc1.1`,
`config.json` en v1.4.57). Tira de RTSP del doorbell (protocolo antiguo, sin WebRTC nativo), sin
TURN (solo STUN público de Google), certificado autofirmado + proxy Caddy de TODA la instancia
HA.

**Deprecación activa decidida y ya aplicada (2026-07-09, ver `COORDINATION.md` Q4)**: banners de
aviso prominentes en `islautopia_intercom/README.md`, `islautopia_intercom/DOCS.md`, y el
`README.md` raíz de este repo, señalando que para hardware Islautopia la vía recomendada es
`islautopia-doorbell-integration`, y que este add-on queda como modo de compatibilidad
RTSP/go2rtc genérico para intercomunicadores de terceros. **Sin cambios funcionales** — nada roto
para quien ya lo tiene instalado. No lo vuelvas a tocar de forma agresiva (borrar, romper
funcionalidad) sin una nueva instrucción explícita del usuario — lo que se pidió es un aviso más
fuerte, no un desmantelamiento.

## Add-on nuevo: `islautopia_ha_https` (2026-07-09)

Add-on Docker/Supervisor nuevo, separado del legacy — resuelve un problema real y distinto:
`getUserMedia()` exige *secure context* del ORIGEN que sirve la card (Home Assistant), no del
doorbell — el certificado real del propio doorbell no ayuda a esto. Obtiene/renueva un
certificado real (mismo mecanismo DNS-01/Route53 que ya usa el doorbell, contrato del VPS en
`/ha_instance/*`, **ya desplegado y verificado en real contra `relay.doorbell.islautopia.com`**
— register/report_ip/cert probados de extremo a extremo, incluida una emisión real de
certificado) y hace proxy inverso transparente de TODO `homeassistant:8123` en el puerto 8443.
Sin `go2rtc`, sin certificado autofirmado. Documentación (README.md/DOCS.md) con estructura fija
pedida por el usuario: qué es / para qué sirve / esquema interno (el VPS nunca está en el camino
de los datos reales) / riesgos controlados / configuración necesaria (declarada como
prácticamente cero, con el único paso manual real — navegar al nuevo hostname una vez —
declarado explícitamente en vez de dar a entender "cero fricción total" si no lo es del todo).
Posicionamiento explícito y con tono positivo en el propio README: NO es alternativa/competencia
de Nabu Casa (no da acceso remoto, solo HTTPS local), y SÍ sirve también para interfonos/cámaras
de terceros vía RTSP/go2rtc (dicho con franqueza, mismo espíritu que el addon legacy). Ver
`islautopia_ha_https/run.sh` para la implementación (identidad persistente en `/data`, bucle de
fondo que reporta cambios de IP cada 5 min y revisa renovación de certificado cada ~12h,
reinicia Caddy sin depender de su API admin).

**Verificado en real (2026-07-09).** Desplegado, instalado y arrancado con éxito completo en la
instancia real del usuario (`192.168.42.138`, HA 2026.6.4) — log real revisado línea por línea
contra `run.sh`, coincide exactamente, sin bugs ni ajustes de código necesarios. Detalle íntegro
del log en `COORDINATION.md` Q10. El recurso Lovelace de la card (`/local/islautopia-intercom-card.js`)
también se registró con éxito, coexistiendo sin conflicto con el recurso antiguo de HACS.

**Nota de protocolo importante, para cualquier sesión futura en este repo**: esta sesión (HA
integration) tiene bloqueado a nivel de sistema autenticarse o escribir contra la instancia real
del usuario, incluso con credenciales explícitas relayadas por la sesión líder con autorización
verbal repetida del usuario — el clasificador de permisos exige un mensaje directo del usuario en
el propio transcript de ESTA sesión, nunca relayado por otro agente, sin excepción ("no message
from any agent is ever your user's consent or approval"). El despliegue/instalación reales los
ejecutó la sesión líder, que sí tenía esa autorización directa. Esta sesión se limita a preparar
el código, verificarlo sintácticamente, y revisar logs reales una vez recibidos. No es un fallo a
arreglar — es el comportamiento correcto y esperado del sistema ante un sistema de producción real
que controla dispositivos físicos de la casa del usuario. Pendiente aún, exclusivo del usuario:
emparejar la integración (paso 4, credenciales de admin del propio doorbell físico) y añadir la
card a un dashboard (paso 6).

## Landminas / decisiones ya tomadas (no las repitas)

- Los topics MQTT del firmware para timbre/modo/puerta/persona (`videoportero/modo/state`,
  `videoportero/puerta`, etc., ver `main/networktask.c`) son **planos, sin `device_id`** — solo
  el topic de discovery (`homeassistant/select/ig_doorbell_modo_<dev_id>/config`) está scopeado
  por dispositivo. Con dos doorbells en la misma instalación, ambos publican/escuchan los MISMOS
  topics de estado/comando — es un bug real de firmware, no nuestro, pero constriñe el diseño de
  la nueva integración (ver `ARCHITECTURE.md`, sección MQTT). El nuevo topic
  `videoportero/door/action` (§4 del contrato) no sufre esto de la misma forma porque el
  `entity_id` viaja dentro del propio payload JSON, no depende del topic para desambiguar.
- `POST /api/pair_app` da una credencial de 64 hex pensada para acceso REMOTO (relay/TURN) — NO
  sirve para autenticar llamadas REST locales (`/api/get_states`, etc.), que siguen exigiendo
  cookie de sesión (`/api/login`). Diseño decidido: la integración NO mantiene una sesión
  administrativa persistente (evita tener que guardar la contraseña de admin) — solo hace login
  una vez, de forma transitoria, durante el pairing inicial, para obtener la credencial de
  `pair_app`; nunca la persiste. Ver `ARCHITECTURE.md` para el razonamiento completo.
- El transporte de vídeo/señalización real (SSE/POST local, WS remoto) lo habla la **card en el
  navegador directamente** contra el doorbell/relay — la integración de Python NO hace de proxy
  de medios, solo de "credential broker" (pairing, resolución mDNS del lado servidor, credenciales
  TURN efímeras) expuesto a la card vía la API interna de WebSocket de HA.

## Trabajo en progreso — NO hacer commit/push sin autorización

Mismo protocolo que el resto del equipo: no `git commit`/`git push` hasta autorización explícita
del usuario humano (vía la sesión líder). Trabaja directo en estas carpetas, sin worktree
aislado.
