#!/bin/bash

echo "Iniciando Islautopia Intercom Engine (Modo Local SSL)..."

# ==============================================================================
# 1. PREPARACIÓN DE DIRECTORIOS Y CONFIGURACIÓN
# ==============================================================================
export XDG_DATA_HOME="/config/islautopia"
export XDG_CONFIG_HOME="/config/islautopia"
mkdir -p /config/islautopia/certs

CONFIG_PATH="/data/options.json"

INTERCOM_IP=$(jq --raw-output '.intercom_ip' $CONFIG_PATH)
PUERTO_WEBRTC=$(jq --raw-output '.puerto_webrtc' $CONFIG_PATH)
NOMBRE_DISPOSITIVO=$(jq --raw-output '.nombre_dispositivo' $CONFIG_PATH)

if [ -z "$INTERCOM_IP" ] || [ "$INTERCOM_IP" = "null" ]; then
    echo "ERROR FATAL: La IP local del videoportero no está configurada."
    exit 1
fi

[ -z "$PUERTO_WEBRTC" ] || [ "$PUERTO_WEBRTC" = "null" ] && PUERTO_WEBRTC="8565"
[ -z "$NOMBRE_DISPOSITIVO" ] || [ "$NOMBRE_DISPOSITIVO" = "null" ] && NOMBRE_DISPOSITIVO="videoportero"

# DETECCIÓN DINÁMICA DE LA IP DE HASS
echo "Detectando IP local de Home Assistant..."
HASS_IP=$(curl -s -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/network/info | jq --raw-output '.data.interfaces[] | select(.primary==true) | .ipv4.address[0]' | cut -d'/' -f1)

if [ -z "$HASS_IP" ] || [ "$HASS_IP" = "null" ]; then
    HASS_IP="192.168.42.138" # Fallback seguro
fi
echo "IP principal de Home Assistant detectada: ${HASS_IP}"

# ==============================================================================
# 2. OPTIMIZACIÓN WEBRTC: GENERACIÓN DINÁMICA DE CANDIDATES (Caja Negra)
# ==============================================================================
echo "Compilando lista de candidatos de red locales..."

# Iniciamos el bloque con la IP que nos da el supervisor
CANDIDATES_BLOCK="    - ${HASS_IP}:${PUERTO_WEBRTC}"

# Forzamos la escucha en la interfaz global (0.0.0.0) para saltar el inter-vlan
CANDIDATES_BLOCK="${CANDIDATES_BLOCK}\n    - 0.0.0.0:${PUERTO_WEBRTC}"

# 🧠 SOLUCIÓN COMPATIBLE CON BUSYBOX (Alpine): Extraemos todas las IPs locales válidas
ALL_IPS=$(ip -4 addr show | awk '/inet / {print $2}' | cut -d'/' -f1)

for ip in $ALL_IPS; do
    # Evitamos duplicar la IP principal y filtramos el localhost (127.0.0.1)
    if [ "$ip" != "$HASS_IP" ] && [ "$ip" != "127.0.0.1" ] && [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        CANDIDATES_BLOCK="${CANDIDATES_BLOCK}\n    - ${ip}:${PUERTO_WEBRTC}"
    fi
done

echo "Generando configuración /etc/go2rtc.yaml..."
cat << EOF > /etc/go2rtc.yaml
api:
  listen: ":1984"

rtsp:
  listen: ":8554"

webrtc:
  listen: ":${PUERTO_WEBRTC}"
  candidates:
$(echo -e "$CANDIDATES_BLOCK")

streams:
  ${NOMBRE_DISPOSITIVO}: rtsp://${INTERCOM_IP}:554/stream
EOF

# ==============================================================================
# 3. GENERACIÓN DEL CERTIFICADO CON OPENSSL (Persistente y controlado)
# ==============================================================================
if ! command -v openssl &> /dev/null; then
    echo "Instalando dependencia OpenSSL..."
    apk add --no-cache openssl
fi

CERT_FILE="/config/islautopia/certs/islautopia.crt"
KEY_FILE="/config/islautopia/certs/islautopia.key"

# VERIFICACIÓN INTELIGENTE: Mantiene el candado verde en Windows sin machacar claves
if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "No se encontró un certificado previo. Generando certificado SSL nuevo..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout "$KEY_FILE" -out "$CERT_FILE" \
      -subj "/CN=${HASS_IP}" \
      -addext "subjectAltName = IP:${HASS_IP},DNS:homeassistant.local,DNS:localhost" 2>/dev/null
else
    echo "Certificado SSL existente detectado. Saltando generación para mantener la confianza de Windows."
fi

# ==============================================================================
# 4. GENERAR EL CADDYFILE PLANO (Aislamiento de API estricto)
# ==============================================================================
echo "Generando Caddyfile..."

cat << EOF > /etc/Caddyfile
{
    admin off
    auto_https disable_redirects
}

:8443 {
    tls ${CERT_FILE} ${KEY_FILE}

    # 1. Descarga del certificado
    handle /root.crt {
        root * /config/islautopia/certs/
        header Content-Disposition "attachment; filename=islautopia.crt"
        header Content-Type "application/x-x509-ca-cert"
        rewrite * /islautopia.crt
        file_server
    }

    # 2. Portal de soporte local
    handle /cert {
        header Content-Type "text/html; charset=utf-8"
        respond <<HTML
<html>
    <head><meta charset="UTF-8"><title>Islautopia Intercom Gateway</title></head>
    <body style="font-family: system-ui, sans-serif; text-align: center; padding: 50px; background: #f4f6f9;">
        <div style="max-width: 550px; margin: auto; background: white; padding: 40px; border-radius: 16px; box-shadow: 0 4px 15px rgba(0,0,0,0.05);">
            <h1>Instalación de Certificado</h1>
            <p>El certificado seguro se ha generado para la IP ${HASS_IP}.</p>
            <div style="background: #f8f9fa; padding: 25px; border-radius: 12px; margin-bottom: 20px;">
                <a href="/root.crt" style="display: inline-block; padding: 14px 28px; background: #007bff; color: white; text-decoration: none; border-radius: 8px; font-weight: bold;">
                    📥 Descargar Certificado (islautopia.crt)
                </a>
            </div>
            <a href="/" style="color: #007bff; text-decoration: none;">Ir a Home Assistant →</a>
        </div>
    </body>
</html>
HTML
    }

    # 3. Filtros exclusivos go2rtc para evitar colisiones con el WebSocket de HA
    handle /api/webrtc* {
        reverse_proxy 127.0.0.1:1984
    }
    handle /api/ws* {
        reverse_proxy 127.0.0.1:1984
    }

    # 4. Proxy transparente hacia el Core de Home Assistant
    handle {
        reverse_proxy homeassistant:8123
    }
}
EOF

# ==============================================================================
# 5. LANZAMIENTO
# ==============================================================================
echo "Iniciando motor de vídeo WebRTC (go2rtc)..."
/usr/local/bin/go2rtc -config /etc/go2rtc.yaml &

echo "Iniciando pasarela HTTPS limpia..."
caddy run --config /etc/Caddyfile --adapter caddyfile