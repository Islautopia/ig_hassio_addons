#!/bin/bash

echo "Iniciando Islautopia Intercom Engine..."

# ==============================================================================
# 1. CONFIGURACIÓN E INYECCIÓN DE VARIABLES
# ==============================================================================
CONFIG_PATH="/data/options.json"

INTERCOM_IP=$(jq --raw-output '.intercom_ip' $CONFIG_PATH)
PUERTO_WEBRTC=$(jq --raw-output '.puerto_webrtc' $CONFIG_PATH)
NOMBRE_DISPOSITIVO=$(jq --raw-output '.nombre_dispositivo' $CONFIG_PATH)

if [ -z "$INTERCOM_IP" ] || [ "$INTERCOM_IP" = "null" ]; then
    echo "ERROR FATAL: La IP del videoportero no está configurada."
    exit 1
fi

[ -z "$NOMBRE_DISPOSITIVO" ] || [ "$NOMBRE_DISPOSITIVO" = "null" ] && NOMBRE_DISPOSITIVO="videoportero"

echo "Configurando stream '${NOMBRE_DISPOSITIVO}'..."
sed -i "s/REPLACE_WITH_STREAM_NAME/${NOMBRE_DISPOSITIVO}/g" /etc/go2rtc.yaml
sed -i "s/REPLACE_WITH_INTERCOM_IP/${INTERCOM_IP}/g" /etc/go2rtc.yaml
sed -i "s/REPLACE_WITH_WEBRTC_PORT/${PUERTO_WEBRTC}/g" /etc/go2rtc.yaml

# ==============================================================================
# 2. GENERAR EL CADDYFILE (A prueba de fallos para Alpine)
# ==============================================================================
echo "Generando Caddyfile optimizado para entorno aislado..."

cat << EOF > /etc/Caddyfile
{
    admin off
    auto_https disable_redirects
}

:8443 {
    # Forzamos a Caddy a usar TLS interno puro sin intentar instalarse en el sistema
    tls internal {
        on_demand
    }
    
    # Proxy para el WebRTC
    reverse_proxy /api/ws* 127.0.0.1:1984
    reverse_proxy /api/webrtc* 127.0.0.1:1984
    reverse_proxy /api/streams* 127.0.0.1:1984
    
    # Proxy para Home Assistant
    reverse_proxy homeassistant:8123
}
EOF

# ==============================================================================
# 3. ARRANCAR MOTORES
# ==============================================================================
echo "Iniciando motor de vídeo WebRTC (go2rtc)..."
/usr/local/bin/go2rtc -config /etc/go2rtc.yaml &

echo "Iniciando pasarela HTTPS..."
# Ejecutamos Caddy directamente. Si no especificamos rutas, 
# usará su carpeta interna por defecto, evitando conflictos de permisos.
caddy run --config /etc/Caddyfile --adapter caddyfile