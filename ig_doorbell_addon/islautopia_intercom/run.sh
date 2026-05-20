#!/bin/bash

echo "Iniciando Islautopia Intercom Engine (Modo Local CA)..."

# ==============================================================================
# 1. LEER CONFIGURACIÓN DEL USUARIO (Vía JQ nativo)
# ==============================================================================
CONFIG_PATH="/data/options.json"

INTERCOM_IP=$(jq --raw-output '.intercom_ip' $CONFIG_PATH)
PUERTO_WEBRTC=$(jq --raw-output '.puerto_webrtc' $CONFIG_PATH)
NOMBRE_DISPOSITIVO=$(jq --raw-output '.nombre_dispositivo' $CONFIG_PATH)

if [ -z "$INTERCOM_IP" ] || [ "$INTERCOM_IP" = "null" ]; then
    echo "ERROR FATAL: La IP local del videoportero no está configurada. Deteniendo."
    exit 1
fi

# Si el usuario lo deja en blanco, ponemos uno por defecto para que no casque
if [ -z "$NOMBRE_DISPOSITIVO" ] || [ "$NOMBRE_DISPOSITIVO" = "null" ]; then
    NOMBRE_DISPOSITIVO="videoportero"
fi

# Inyectamos las variables en go2rtc
echo "Configurando stream '${NOMBRE_DISPOSITIVO}' hacia la IP: ${INTERCOM_IP}..."
sed -i "s/REPLACE_WITH_STREAM_NAME/${NOMBRE_DISPOSITIVO}/g" /etc/go2rtc.yaml
sed -i "s/REPLACE_WITH_INTERCOM_IP/${INTERCOM_IP}/g" /etc/go2rtc.yaml

echo "Configurando puerto WebRTC en: ${PUERTO_WEBRTC}..."
sed -i "s/REPLACE_WITH_WEBRTC_PORT/${PUERTO_WEBRTC}/g" /etc/go2rtc.yaml

# ==============================================================================
# 2. GENERAR EL CADDYFILE DINÁMICAMENTE (Cifrado Local)
# ==============================================================================
echo "Generando Caddyfile con Autoridad de Certificación Interna..."

cat << EOF > /etc/Caddyfile
{
    admin off
    default_sni homeassistant.local
}

homeassistant.local:8443, :8443 {
    tls internal

    handle /root.crt {
            root * /config/islautopia/caddy/pki/authorities/local/
            file_server
        }

    @go2rtc {
        path /api/ws*
        path /api/webrtc*
        path /api/streams*
    }
    handle @go2rtc {
        reverse_proxy 127.0.0.1:1984
    }
    
    handle {
        reverse_proxy homeassistant:8123
    }
}
EOF

# ==============================================================================
# 3. ARRANCAR LOS MOTORES EN PARALELO
# ==============================================================================

echo "Iniciando motor de vídeo WebRTC (go2rtc)..."
/usr/local/bin/go2rtc -config /etc/go2rtc.yaml &

echo "Iniciando pasarela HTTPS Local Autónoma (Caddy)..."
# Apuntamos a la carpeta de configuración donde reside configuration.yaml
export XDG_DATA_HOME="/config/islautopia"
export XDG_CONFIG_HOME="/config/islautopia"

caddy run --config /etc/Caddyfile --adapter caddyfile --env CADDY_DATA=/config/islautopia
