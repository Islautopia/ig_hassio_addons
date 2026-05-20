#!/bin/bash

echo "Iniciando Islautopia Intercom Engine (Modo Local CA)..."

# ==============================================================================
# 1. PREPARACIÓN DE DIRECTORIOS Y VARIABLES (Persistencia en /config)
# ==============================================================================
# Forzamos a Caddy a guardar sus datos en la carpeta compartida con Home Assistant
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
# 2. GENERAR EL CADDYFILE (Diferenciando HASS de la descarga del Certificado)
# ==============================================================================
echo "Generando Caddyfile optimizado con redirecciones correctas..."

cat << EOF > /etc/Caddyfile
{
    admin off
    auto_https disable_redirects
}

:8443 {
    tls internal {
        on_demand
    }

    # 1. Endpoint directo para la descarga del archivo físico
    handle /root.crt {
        root * /config/islautopia/caddy/pki/authorities/local/
        
        # Forzamos al navegador a descargarlo en lugar de mostrarlo
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
            <p style="color: #666; margin-bottom: 30px;">Descarga e instala el certificado raíz para habilitar el audio bidireccional seguro.</p>
            
            <div style="background: #f8f9fa; border: 1px solid #e9ecef; padding: 25px; border-radius: 12px; margin-bottom: 20px;">
                <a href="/root.crt" style="display: inline-block; padding: 14px 28px; background: #007bff; color: white; text-decoration: none; border-radius: 8px; font-weight: bold; box-shadow: 0 2px 5px rgba(0,123,255,0.2);">
                    📥 Descargar Certificado Raíz (root.crt)
                </a>
                <p style="margin-top: 15px; font-size: 0.9em; color: #555; line-height: 1.5; text-align: left;">
                    <b>Instrucciones rápidas:</b><br>
                    • <b>Windows/PC:</b> Doble clic al archivo → Instalar → Equipo local → Colocar en "Entidades de certificación raíz de confianza".<br>
                    • <b>Móvil:</b> Ajustes → Seguridad → Instalar desde almacenamiento → Certificado de CA.
                </p>
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

    # 4. LA RAÍZ VA A HASS: Todo lo que no sea /cert o /root.crt va directo a Home Assistant
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