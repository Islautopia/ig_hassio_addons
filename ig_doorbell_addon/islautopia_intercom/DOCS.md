# Islautopia Intercom & SSL Gateway

Este Add-on es el corazón de tu videoportero Islautopia. Se encarga de dos tareas vitales:
1. Gestionar el motor de vídeo ultra-rápido (WebRTC) para que el audio y el vídeo fluyan sin retardo.
2. Crear un túnel seguro (HTTPS) automático para que puedas contestar desde cualquier lugar del mundo de forma segura y sin que el navegador bloquee tu micrófono.

## 🚀 Instalación y Configuración (Modo Novato)

Si no tienes acceso externo configurado en tu Home Assistant, sigue estos pasos:

**Paso 1: Consigue tu Dominio Gratuito**
1. Entra en [DuckDNS.org](https://www.duckdns.org) e inicia sesión (puedes usar Google).
2. En la casilla "sub domain", inventa un nombre y pulsa **"add domain"**.
3. Copia tu nuevo dominio (ej. `micasa.duckdns.org`) y tu **Token** (una clave larga de letras y números que aparece arriba en la web).

**Paso 2: Configura el Add-on**
1. Ve a la pestaña **Configuración** de este Add-on.
2. Pon la IP local de tu videoportero (ESP32-P4).
3. Asegúrate de que el Modo de Operación es **DuckDNS Auto**.
4. Pega el Dominio y el Token que copiaste en el Paso 1.
5. Guarda e Inicia el Add-on.

**Paso 3: Avisa a Home Assistant**
Para que Home Assistant acepte este nuevo túnel seguro, debes añadir esto a tu archivo `configuration.yaml` y reiniciar Home Assistant:

\`\`\`yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.30.33.0/24
\`\`\`

**Paso 4: Actualiza tu URL Externa**
Ve a **Ajustes > Sistema > Red** en tu Home Assistant, y en "URL de Home Assistant" (acceso externo), escribe tu nuevo dominio con https (ej. `https://micasa.duckdns.org`).

¡Listo! Ya tienes acceso seguro desde cualquier lugar.

---

## 🛠️ Instalación (Usuarios Avanzados)

Si ya tienes tu propio proxy inverso (Nginx Proxy Manager, Cloudflare, Nabu Casa, o Caddy externo):
1. En la pestaña Configuración, selecciona **Certificados Locales**.
2. Rellena las rutas a tus certificados (si aplican) o usa tu proxy existente para redirigir el tráfico del puerto `8123` (HASS) y `8555`/`1984` (WebRTC).