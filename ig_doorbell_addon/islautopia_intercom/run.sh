#!/bin/bash

echo "Iniciando Islautopia Intercom Engine (Modo Local CA)..."

# ==============================================================================
# 1. PREPARACIÓN DE DIRECTORIOS Y VARIABLES
# ==============================================================================
# Aseguramos que la carpeta persista en /config/islautopia
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

echo "Configurando stream '${NOMBRE_DISPOSITIVO}' hacia la IP: ${INTERCOM_IP}..."
sed -i "s/REPLACE_WITH_STREAM_NAME/${NOMBRE_DISPOSITIVO}/g" /etc/go2rtc.yaml
sed -i "s/REPLACE_WITH_INTERCOM_IP/${INTERCOM_IP}/g" /etc/go2rtc.yaml
sed -i "s/REPLACE_WITH_WEBRTC_PORT/${PUERTO_WEBRTC}/g" /etc/go2rtc.yaml

# ==============================================================================
# 2. GENERAR EL CADDYFILE (Con Landing Page de descarga)
# ==============================================================================
echo "Generando Caddyfile con Autoridad de Certificación Interna..."

cat << EOF > /etc/Caddyfile
{
    admin off
    # Deshabilitamos la gestión automática de puertos
    auto_https off
}

:8443 {
    # CORRECTO: self_signed debe ir dentro de llaves
    tls {
        self_signed
    }
    
    handle / {
        respond "Si esto carga, el SSL funciona"
    }
}
EOF

# ==============================================================================
# 3. ARRANCAR MOTORES
# ==============================================================================

echo "Iniciando motor de vídeo WebRTC (go2rtc)..."
/usr/local/bin/go2rtc -config /etc/go2rtc.yaml &

echo "Iniciando pasarela HTTPS Local Autónoma (Caddy)..."
caddy run --config /etc/Caddyfile --adapter caddyfile