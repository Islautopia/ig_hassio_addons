#!/bin/bash

echo "Starting Islautopia Intercom Engine (Local SSL Mode)..."

# ==============================================================================
# 1. DIRECTORY PREPARATION & CONFIGURATION
# ==============================================================================
export XDG_DATA_HOME="/config/islautopia"
export XDG_CONFIG_HOME="/config/islautopia"
mkdir -p /config/islautopia/certs

CONFIG_PATH="/data/options.json"

# Extract parameters using the new English keys
INTERCOM_IP=$(jq --raw-output '.intercom_ip' $CONFIG_PATH)
WEBRTC_PORT=$(jq --raw-output '.webrtc_port' $CONFIG_PATH)
DEVICE_NAME=$(jq --raw-output '.device_name' $CONFIG_PATH)
GO2RTC_PORT=$(jq --raw-output '.go2rtc_api_port' $CONFIG_PATH)

if [ -z "$INTERCOM_IP" ] || [ "$INTERCOM_IP" = "null" ]; then
    echo "FATAL ERROR: Intercom local IP is not configured."
    exit 1
fi

[ -z "$WEBRTC_PORT" ] || [ "$WEBRTC_PORT" = "null" ] && WEBRTC_PORT="8565"
[ -z "$DEVICE_NAME" ] || [ "$DEVICE_NAME" = "null" ] && DEVICE_NAME="videoportero"
[ -z "$GO2RTC_PORT" ] || [ "$GO2RTC_PORT" = "null" ] && GO2RTC_PORT="1985"

# DYNAMIC HA IP DETECTION
echo "Detecting Home Assistant local IP..."
HASS_IP=$(curl -s -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/network/info | jq --raw-output '.data.interfaces[] | select(.primary==true) | .ipv4.address[0]' | cut -d'/' -f1)

if [ -z "$HASS_IP" ] || [ "$HASS_IP" = "null" ]; then
    HASS_IP="192.168.42.138" # Safe fallback
fi
echo "Main Home Assistant IP detected: ${HASS_IP}"

# ==============================================================================
# 2. WEBRTC OPTIMIZATION: DYNAMIC CANDIDATE GENERATION
# ==============================================================================
echo "Compiling local network candidates list..."

# Start with the supervisor IP
CANDIDATES_BLOCK="    - ${HASS_IP}:${WEBRTC_PORT}"

# Force listening on global interface (0.0.0.0) to bypass inter-vlan issues
CANDIDATES_BLOCK="${CANDIDATES_BLOCK}\n    - 0.0.0.0:${WEBRTC_PORT}"

# BUSYBOX COMPATIBLE: Extract all valid local IPs
ALL_IPS=$(ip -4 addr show | awk '/inet / {print $2}' | cut -d'/' -f1)

for ip in $ALL_IPS; do
    # Avoid duplicating main IP and filter localhost
    if [ "$ip" != "$HASS_IP" ] && [ "$ip" != "127.0.0.1" ] && [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        CANDIDATES_BLOCK="${CANDIDATES_BLOCK}\n    - ${ip}:${WEBRTC_PORT}"
    fi
done

echo "Generating /etc/go2rtc.yaml configuration..."
cat << EOF > /etc/go2rtc.yaml
api:
  origin: "*"
  listen: ":${GO2RTC_PORT}"

rtsp:
  listen: ":8554"

webrtc:
  listen: ":${WEBRTC_PORT}"
  candidates:
$(echo -e "$CANDIDATES_BLOCK")
    - stun:stun.l.google.com:19302

streams:
  ${DEVICE_NAME}: rtsp://${INTERCOM_IP}:554/stream
EOF

# ==============================================================================
# 3. OPENSSL CERTIFICATE GENERATION (Persistent & Controlled)
# ==============================================================================
if ! command -v openssl &> /dev/null; then
    echo "Installing OpenSSL dependency..."
    apk add --no-cache openssl
fi

CERT_FILE="/config/islautopia/certs/islautopia.crt"
KEY_FILE="/config/islautopia/certs/islautopia.key"

# SMART CHECK: Keeps green padlock on Windows without overwriting keys
if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "No previous certificate found. Generating new SSL certificate..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout "$KEY_FILE" -out "$CERT_FILE" \
      -subj "/CN=${HASS_IP}" \
      -addext "subjectAltName = IP:${HASS_IP},DNS:homeassistant.local,DNS:localhost" 2>/dev/null
else
    echo "Existing SSL certificate detected. Skipping generation to maintain Windows trust."
fi

# ==============================================================================
# 4. FLAT CADDYFILE GENERATION (Strict API isolation and WebSockets)
# ==============================================================================
echo "Generating Caddyfile..."

cat << EOF > /etc/Caddyfile
{
    admin off
    auto_https disable_redirects
}

:8443 {
    tls ${CERT_FILE} ${KEY_FILE}

    # 1. Certificate download endpoint
    handle /root.crt {
        root * /config/islautopia/certs/
        header Content-Disposition "attachment; filename=islautopia.crt"
        header Content-Type "application/x-x509-ca-cert"
        rewrite * /islautopia.crt
        file_server
    }

    # 2. Local support portal
    handle /cert {
        header Content-Type "text/html; charset=utf-8"
        respond <<HTML
<html>
    <head><meta charset="UTF-8"><title>Islautopia Intercom Gateway</title></head>
    <body style="font-family: system-ui, sans-serif; text-align: center; padding: 50px; background: #f4f6f9;">
        <div style="max-width: 550px; margin: auto; background: white; padding: 40px; border-radius: 16px; box-shadow: 0 4px 15px rgba(0,0,0,0.05);">
            <h1>Certificate Installation</h1>
            <p>The secure certificate has been generated for IP ${HASS_IP}.</p>
            <div style="background: #f8f9fa; padding: 25px; border-radius: 12px; margin-bottom: 20px;">
                <a href="/root.crt" style="display: inline-block; padding: 14px 28px; background: #007bff; color: white; text-decoration: none; border-radius: 8px; font-weight: bold;">
                    📥 Download Certificate (islautopia.crt)
                </a>
            </div>
            <a href="/" style="color: #007bff; text-decoration: none;">Go to Home Assistant →</a>
        </div>
    </body>
</html>
HTML
    }

    # 3. Exclusive go2rtc filters to avoid collisions with HA WebSocket
    handle /api/webrtc* {
        reverse_proxy 127.0.0.1:${GO2RTC_PORT}
    }
    handle /api/ws* {
        reverse_proxy 127.0.0.1:${GO2RTC_PORT} {
            header_up Upgrade {header.Upgrade}
            header_up Connection {header.Connection}
        }
    }

    # 4. Transparent proxy to Home Assistant Core
    handle {
        reverse_proxy homeassistant:8123
    }
}
EOF

# ==============================================================================
# 5. LAUNCH & DASHBOARD LOGS
# ==============================================================================
echo "Starting WebRTC video engine (go2rtc)..."
/usr/local/bin/go2rtc -config /etc/go2rtc.yaml &

# Brief pause to ensure endpoints are bound before printing dashboard
sleep 2

echo ""
echo "=================================================================="
echo " 🎉 Islautopia Intercom Engine is successfully running!"
echo "=================================================================="
echo " 🔐 Secure Home Assistant Access URL:"
echo "    👉 https://${HASS_IP}:8443"
echo ""
echo " 🎥 Integrated go2rtc WebUI/API URL:"
echo "    👉 http://${HASS_IP}:${GO2RTC_PORT}"
echo ""
echo " ℹ️  CRITICAL STEP FOR 2-WAY AUDIO (Microphone Access):"
echo "    Modern web browsers block microphone permissions on untrusted links."
echo "    To enable 2-way audio on EACH device (phone, tablet, or PC):"
echo "    1. Open your browser and navigate to: https://${HASS_IP}:8443/cert"
echo "    2. Click the download button to get 'islautopia.crt'."
echo "    3. Open the downloaded file and install/import it into your"
echo "       device's 'Trusted Root Certification Authorities' store."
echo "=================================================================="
echo ""

echo "Starting clean HTTPS gateway..."
caddy run --config /etc/Caddyfile --adapter caddyfile