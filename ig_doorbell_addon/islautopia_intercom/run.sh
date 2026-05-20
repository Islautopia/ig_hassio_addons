#!/bin/bash

echo "Iniciando Islautopia Intercom Engine (Modo Local CA)..."

# ==============================================================================
# 1. PREPARACIÓN DE DIRECTORIOS Y DETECCIÓN DE IPS
# ==============================================================================
export XDG_DATA_HOME="/config/islautopia"
export XDG_CONFIG_HOME="/config/islautopia"
mkdir -p /config/islautopia

CONFIG_PATH="/data/options.json"

INTERCOM_IP=$(jq --raw-output '.intercom_ip' $CONFIG_PATH)
PUERTO_WEBRTC=$(jq --raw-output '.puerto_webrtc' $CONFIG_PATH)
NOMBRE_DISPOSITIVO=$(jq --raw-output '.nombre_dispositivo' $CONFIG_PATH)

if [ -z "$INTERCOM_IP" ] || [ "$INTERCOM_IP" = "null" ]; then
    echo "ERROR FATAL: La IP local del videoportero no está configurada."
    exit 1
fi

[ -z "$NOMBRE_DISPOSITIVO" ] || [ "$NOMBRE_DISPOSITIVO" = "null" ] && NOMBRE_DISPOSITIVO="videoportero"

# 🔍 DETECCIÓN DINÁMICA DE LA IP DE HOME ASSISTANT
# Consultamos a la API del Supervisor usando el token nativo del contenedor
echo "Detectando IP local de Home Assistant..."
HASS_IP=$(curl -s -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/network/info | jq --raw-output '.data.interfaces[] | select(.primary==true) | .ipv4.address[0]' | cut -d'/' -f1)

# Si por algún motivo falla la API, ponemos un fallback seguro
if [ -z "$HASS_IP" ] || [ "$HASS_IP" = "null" ]; then
    echo "Aviso: No se pudo detectar la IP por API, usando nombres locales por defecto."
    HASS_IP="homeassistant.local"
else
    echo "IP de Home Assistant detectada con éxito: ${HASS_IP}"
fi

# Inyección en go2rtc
echo "Configurando stream '${NOMBRE_DISPOSITIVO}' hacia la IP: ${INTERCOM_IP}..."
sed -i "s/REPLACE_WITH_STREAM_NAME/${NOMBRE_DISPOSITIVO}/g" /etc/go2rtc.yaml
sed -i "s/REPLACE_WITH_INTERCOM_IP/${INTERCOM_IP}/g" /etc/go2rtc.yaml
sed -i "s/REPLACE_WITH_WEBRTC_PORT/${PUERTO_WEBRTC}/g" /etc/go2rtc.yaml

# ==============================================================================
# 2. GENERAR EL CADDYFILE DINÁMICO (Solución definitiva Handshake IP)
# ==============================================================================
echo "Generando Caddyfile dinámico con emisor local puro..."

cat << EOF > /etc/Caddyfile
{
    admin off
    auto_https disable_redirects
}

# Forzamos la escucha en el puerto con los hosts limpios
${CADDY_HOSTS} {
    # Configuramos el TLS interno indicando explícitamente el emisor local
    tls internal {
        on_demand
        issuer internal {
            ca local
        }
    }

    # 1. Endpoint directo para la descarga del archivo físico
    handle /root.crt {
        root * /config/islautopia/caddy/pki/authorities/local/
        header Content-Disposition "attachment; filename=root.crt"
        header Content-Type "application/x-x509-ca-cert"
        file_server
    }

    # 2. RUTA EXCLUSIVA PARA EL SOPORTE: Explicación y descarga
    handle /cert {
        header Content-Type "text/html; charset=utf-8"
        respond <<HTML
<html>
    <head>
        <meta charset="UTF-8">
        <title>Islautopia Intercom Gateway</title>
    </head>
    <body style="font-family: system-ui, -apple-system, sans-serif; text-align: center; padding: 50px; background: #f4f6f9; color: #333;">
        <div style="max-width: 550px; margin: auto; background: white; padding: 40px; border-radius: 16px; box-shadow: 0 4px 15px rgba(0,0,0,0.05);">
            <h1 style="color: #1a1a1a; margin-bottom: 10px;">Instalación de Certificado</h1>
            <p style="color: #666; margin-bottom: 30px;">El certificado raíz está listo para la dirección: ${HASS_IP}.</p>
            <div style="background: #f8f9fa; border: 1px solid #e9ecef; padding: 25px; border-radius: 12px; margin-bottom: 20px;">
                <a href="/root.crt" style="display: inline-block; padding: 14px 28px; background: #007bff; color: white; text-decoration: none; border-radius: 8px; font-weight: bold;">
                    📥 Descargar root.crt
                </a>
            </div>
            <a href="/" style="color: #007bff; text-decoration: none; font-size: 0.95em;">Ir a Home Assistant →</a>
        </div>
    </body>
</html>
HTML
    }

    # 3. Proxies para el ecosistema WebRTC de go2rtc
    reverse_proxy /api/ws* 127.0.0.1:1984
    reverse_proxy /api/webrtc* 127.0.0.1:1984
    reverse_proxy /api/streams* 127.0.0.1:1984

    # 4. LA RAÍZ VA A HASS
    handle {
        reverse_proxy homeassistant:8123
    }
}
EOF

# ==============================================================================
# 3. ARRANCAR MOTORES
# ==============================================================================
echo "Iniciando motor de vídeo WebRTC (go2rtc)..."
/usr/local/bin/go2rtc -config /etc/go2rtc.yaml &

echo "Iniciando pasarela HTTPS..."
caddy run --config /etc/Caddyfile --adapter caddyfile