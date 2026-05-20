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
    default_sni homeassistant.local
}

:8443 {
    tls internal

    # Ruta para descargar el certificado directamente
    handle /root.crt {
        root * /config/islautopia/caddy/pki/authorities/local/
        file_server
    }

    # Página de bienvenida profesional
    handle / {
        respond \`
        <html>
            <body style="font-family: sans-serif; text-align: center; padding: 50px; background: #f0f2f5;">
                <div style="max-width: 600px; margin: auto; background: white; padding: 30px; border-radius: 12px; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
                    <h1>Islautopia Intercom</h1>
                    <p>El motor está funcionando correctamente.</p>
                    <a href="/root.crt" style="display: inline-block; margin: 20px 0; padding: 15px 25px; background: #007bff; color: white; text-decoration: none; border-radius: 6px; font-weight: bold;">
                        📥 Descargar Certificado Raíz (root.crt)
                    </a>
                    <p style="font-size: 0.85em; color: #666;">
                        Instala este archivo en tu dispositivo para eliminar los errores de seguridad SSL.
                    </p>
                </div>
            </body>
        </html>
        \`
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
# 3. ARRANCAR MOTORES
# ==============================================================================

echo "Iniciando motor de vídeo WebRTC (go2rtc)..."
/usr/local/bin/go2rtc -config /etc/go2rtc.yaml &

echo "Iniciando pasarela HTTPS Local Autónoma (Caddy)..."
caddy run --config /etc/Caddyfile --adapter caddyfile