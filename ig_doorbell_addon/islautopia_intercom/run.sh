#!/bin/bash

echo "Iniciando Islautopia Intercom Engine (Modo Local SSL)..."

# ==============================================================================
# 1. PREPARACIÓN DE DIRECTORIOS Y DETECCIÓN DE IPS
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

[ -z "$NOMBRE_DISPOSITIVO" ] || [ "$NOMBRE_DISPOSITIVO" = "null" ] && NOMBRE_DISPOSITIVO="videoportero"

# DETECCIÓN DE LA IP DE HASS
echo "Detectando IP local de Home Assistant..."
HASS_IP=$(curl -s -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/network/info | jq --raw-output '.data.interfaces[] | select(.primary==true) | .ipv4.address[0]' | cut -d'/' -f1)

if [ -z "$HASS_IP" ] || [ "$HASS_IP" = "null" ]; then
    HASS_IP="192.168.42.138" # Fallback seguro
fi
echo "IP de Home Assistant detectada: ${HASS_IP}"

# Inyección en go2rtc
sed -i "s/REPLACE_WITH_STREAM_NAME/${NOMBRE_DISPOSITIVO}/g" /etc/go2rtc.yaml
sed -i "s/REPLACE_WITH_INTERCOM_IP/${INTERCOM_IP}/g" /etc/go2rtc.yaml
sed -i "s/REPLACE_WITH_WEBRTC_PORT/${PUERTO_WEBRTC}/g" /etc/go2rtc.yaml

# ==============================================================================
# 2. GENERACIÓN DEL CERTIFICADO CON OPENSSL (Evita el bug de OCSP de Caddy)
# ==============================================================================
# Instalamos openssl de forma rápida si la imagen base no lo tuviera
if ! command -v openssl &> /dev/null; then
    echo "Instalando dependencia OpenSSL..."
    apk add --no-cache openssl
fi

CERT_FILE="/config/islautopia/certs/islautopia.crt"
KEY_FILE="/config/islautopia/certs/islautopia.key"

echo "Generando certificado SSL con SAN para la IP: ${HASS_IP}..."

# Generamos el certificado inyectando la IP en el bloque SAN de forma obligatoria
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout "$KEY_FILE" -out "$CERT_FILE" \
  -subj "/CN=${HASS_IP}" \
  -addext "subjectAltName = IP:${HASS_IP},DNS:homeassistant.local,DNS:localhost" 2>/dev/null

# ==============================================================================
# 3. GENERAR EL CADDYFILE PLANO (Proxies corregidos para POST y WS)
# ==============================================================================
echo "Generando Caddyfile..."

cat << EOF > /etc/Caddyfile
{
    admin off
    auto_https disable_redirects
}

:8443 {
    # Le pasamos los archivos generados por OpenSSL
    tls ${CERT_FILE} ${KEY_FILE}

    # 1. Endpoint directo para descargar el certificado
    handle /root.crt {
        root * /config/islautopia/certs/
        header Content-Disposition "attachment; filename=islautopia.crt"
        header Content-Type "application/x-x509-ca-cert"
        rewrite * /islautopia.crt
        file_server
    }

    # 2. RUTA EXCLUSIVA PARA EL SOPORTE
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

    # 3. PARCHE CRÍTICO: Redirección universal de la API de go2rtc (Sintaxis correcta)
    # Cualquier petición a /api/ws, /api/webrtc o /api/streams irá de cabeza a go2rtc
    handle /api/* {
        reverse_proxy 127.0.0.1:1984
    }

    # 4. LA RAÍZ VA A HASS
    handle {
        reverse_proxy homeassistant:8123
    }
}
EOF

# ==============================================================================
# 4. ARRANCAR MOTORES
# ==============================================================================
echo "Iniciando motor de vídeo WebRTC (go2rtc)..."
/usr/local/bin/go2rtc -config /etc/go2rtc.yaml &

echo "Iniciando pasarela HTTPS limpia..."
caddy run --config /etc/Caddyfile --adapter caddyfile