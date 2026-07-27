#!/bin/bash
set -u

echo "Starting Islautopia HTTPS for Home Assistant..."

# ==============================================================================
# 0. PATHS & CONSTANTS
# ==============================================================================
DATA_DIR="/data"
IDENTITY_FILE="$DATA_DIR/ha_instance.json"
CERT_DIR="$DATA_DIR/certs"
CERT_FILE="$CERT_DIR/fullchain.pem"
KEY_FILE="$CERT_DIR/privkey.pem"
HASH_FILE="$CERT_DIR/cert.hash"
LAST_IP_FILE="$DATA_DIR/last_ip"
LAST_CERT_CHECK_FILE="$DATA_DIR/last_cert_check"
CADDYFILE="/etc/Caddyfile"

# Confirmado 2026-07-09: mismo host que ya usa el propio doorbell para /register
# (main/cloud_client.c::RELAY_HOST en IG_Doorbell). Contrato /ha_instance/* verificado en
# real contra este mismo host (register/report_ip/cert probados de extremo a extremo,
# incluida una emision real de certificado Let's Encrypt) - ver COORDINATION.md.
API_BASE="https://relay.doorbell.islautopia.com"

# Dominio publico que la nube asocia a esta instancia (siempre resuelve a la IP LOCAL que le
# reportamos - nunca hace que Home Assistant sea accesible desde fuera de la LAN, ver README.md
# "Seguridad y privacidad").
DOMAIN_SUFFIX="ha.doorbell.islautopia.com"

mkdir -p "$CERT_DIR"

# ==============================================================================
# COLOR / HYPERLINK HELPERS — resaltar la URL de acceso en el log de arranque (peticion del
# usuario, 2026-07-09). Los codigos ANSI de color (CSI, ESC[...m) se renderizan bien en el
# visor de logs del Supervisor de HA (confirmado, ya los usan otros add-ons del ecosistema).
#
# El envoltorio de hyperlink usa OSC 8 (ESC]8;;URL ST TEXTO ESC]8;;ST) para intentar que la URL
# sea clicable en terminales/visores que lo soporten (el mismo truco que usan `ls --hyperlink` o
# pytest) - NO VERIFICADO todavia contra el visor de logs real del Supervisor de HA en la version
# concreta que use cada usuario (no hay forma de comprobar el renderizado real sin verlo en
# pantalla). Es de bajo riesgo aun si no se soporta: una secuencia OSC bien terminada (con ST) la
# consumen en silencio los terminales/visores que no la entienden - el texto visible (el propio
# ANCHOR, que aqui es la URL) sigue mostrandose normal. Si algun dia se confirma que el visor de
# HA SI muestra bytes de escape en crudo en vez de consumirlos, quitar OSC8_START/OSC8_END de
# print_highlighted_url() y dejar solo el color (confirmado que ese si funciona).
#
# Los bytes ESC se construyen con comillas ANSI-C ($'\033', interpretadas por el propio shell al
# analizar el script) en vez de dejar el texto literal "\033" para que lo interprete printf en
# tiempo de ejecucion - un primer intento con printf demostro ser fragil: varias secuencias
# "\033" consecutivas en el mismo format string, con un "\\" de por medio (el terminador ST),
# NO se expandian todas correctamente (verificado con `cat -A`, quedaba texto literal
# "\033[0m" sin convertir). Con $'\033' el byte ESC ya existe de verdad antes de llegar a
# printf, así que no hay ninguna interpretacion de escapes de la que depender ahi.
ESC=$'\033'
readonly ESC
readonly ANSI_RESET="${ESC}[0m"
readonly ANSI_BOLD_CYAN="${ESC}[1;36m"

print_highlighted_url() {
    local url="$1"
    local osc8_start="${ESC}]8;;${url}${ESC}\\"
    local osc8_end="${ESC}]8;;${ESC}\\"
    printf '%s%s%s%s%s\n' "$ANSI_BOLD_CYAN" "$osc8_start" "$url" "$osc8_end" "$ANSI_RESET"
}

# ==============================================================================
# 1. IDENTIDAD PROPIA DEL ADD-ON (una sola vez, nunca se repite mientras exista el fichero)
# ==============================================================================
# A diferencia de /register del propio doorbell (idempotente por MAC), una instancia de HA no
# tiene ningun identificador de fabrica - POST /ha_instance/register crea SIEMPRE una identidad
# nueva. Por eso esto se guarda en /data (volumen persistente propio del add-on, sobrevive
# reinicios/actualizaciones del add-on) y solo se llama si el fichero no existe todavia.
if [ ! -f "$IDENTITY_FILE" ]; then
    echo "Sin identidad propia todavia - registrando esta instancia de Home Assistant..."
    register_response=$(curl -sS -X POST "$API_BASE/ha_instance/register" --max-time 30)

    ha_instance_id=$(echo "$register_response" | jq --raw-output '.ha_instance_id // empty')
    ha_secret=$(echo "$register_response" | jq --raw-output '.ha_secret // empty')

    if [ -z "$ha_instance_id" ] || [ -z "$ha_secret" ]; then
        echo "FATAL: no se pudo registrar esta instancia en la nube."
        echo "Respuesta recibida: $register_response"
        exit 1
    fi

    printf '{"ha_instance_id":"%s","ha_secret":"%s"}' "$ha_instance_id" "$ha_secret" > "$IDENTITY_FILE"
    chmod 600 "$IDENTITY_FILE"
    echo "Nueva identidad registrada: $ha_instance_id"
else
    ha_instance_id=$(jq --raw-output '.ha_instance_id' "$IDENTITY_FILE")
    ha_secret=$(jq --raw-output '.ha_secret' "$IDENTITY_FILE")
    echo "Identidad existente cargada: $ha_instance_id"
fi

HOSTNAME_PUBLIC="${ha_instance_id}.${DOMAIN_SUFFIX}"

# Aviso temprano (peticion del usuario, 2026-07-09): mostrar la URL de acceso YA, nada mas
# conocerla, ademas del banner de "esta funcionando" al final (seccion 5) - el arranque real
# (deteccion de IP + emision/lectura de certificado) puede tardar unos segundos mas, y asi el
# usuario ve de inmediato hacia donde tiene que mirar sin tener que esperar ni hacer scroll.
echo ""
echo "=================================================================="
echo " Islautopia HTTPS for Home Assistant - arrancando"
echo "=================================================================="
echo " Tu URL de acceso local (guardala/marcala como favorita):"
print_highlighted_url "https://${HOSTNAME_PUBLIC}:8443"
echo " Para que el resto de Home Assistant (enlaces, notificaciones, la"
echo " app movil) la use automaticamente, configurala en:"
echo " Ajustes -> Sistema -> Red -> URL de Home Assistant."
echo " (Todavia arrancando el resto del add-on - esta URL estara"
echo " realmente lista en unos segundos, ver el aviso final abajo)"
echo "=================================================================="
echo ""

# ==============================================================================
# 2. DETECCION DE IP LOCAL (misma tecnica que el add-on legacy islautopia_intercom: API del
#    propio Supervisor, no adivinamos interfaces a mano)
# ==============================================================================
detect_local_ip() {
    curl -s -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" http://supervisor/network/info \
        | jq --raw-output '.data.interfaces[] | select(.primary==true) | .ipv4.address[0]' \
        | cut -d'/' -f1
}

report_ip_if_changed() {
    local ip
    ip=$(detect_local_ip)
    if [ -z "$ip" ] || [ "$ip" = "null" ]; then
        echo "No se pudo detectar la IP local via el Supervisor - se omite report_ip esta vez."
        return
    fi

    local last=""
    [ -f "$LAST_IP_FILE" ] && last=$(cat "$LAST_IP_FILE")

    if [ "$ip" != "$last" ]; then
        echo "IP local: $ip (antes: ${last:-ninguna conocida}) - actualizando registro DNS..."
        curl -sS -X POST "$API_BASE/ha_instance/${ha_instance_id}/report_ip" \
            -H "Authorization: Bearer ${ha_secret}" \
            -H "Content-Type: application/json" \
            -d "{\"ip\":\"${ip}\"}" \
            --max-time 15 -o /dev/null
        echo "$ip" > "$LAST_IP_FILE"
    fi
}

report_ip_if_changed

# ==============================================================================
# 3. CERTIFICADO REAL. La primera llamada puede tardar decenas de segundos (emision ACME real
#    en el VPS) - de ahi el timeout generoso. Llamadas siguientes devuelven el cert cacheado al
#    instante. Compara el hash contra lo que ya hay en disco antes de reescribir/recargar, igual
#    que hace https_cert_task.c en el propio firmware del doorbell.
# ==============================================================================
fetch_cert() {
    echo "Solicitando certificado para ${HOSTNAME_PUBLIC}..."
    local response
    response=$(curl -sS -X GET "$API_BASE/ha_instance/${ha_instance_id}/cert" \
        -H "Authorization: Bearer ${ha_secret}" \
        --max-time 120)

    local new_hash
    new_hash=$(echo "$response" | jq --raw-output '.hash // empty')
    if [ -z "$new_hash" ]; then
        echo "AVISO: respuesta de /cert sin 'hash' valido - se mantiene el certificado actual (si hay alguno)."
        echo "Respuesta recibida: $response"
        return 1
    fi

    local old_hash=""
    [ -f "$HASH_FILE" ] && old_hash=$(cat "$HASH_FILE")

    if [ "$new_hash" = "$old_hash" ] && [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
        echo "Certificado sin cambios (hash $new_hash)."
        return 1
    fi

    echo "$response" | jq --raw-output '.cert' > "$CERT_FILE"
    echo "$response" | jq --raw-output '.key' > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    echo "$new_hash" > "$HASH_FILE"
    echo "Certificado actualizado (hash $new_hash)."
    return 0
}

fetch_cert
fetch_cert_result=$?

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "FATAL: no hay certificado disponible (ni en la nube ni en cache local) - no se puede arrancar HTTPS."
    exit 1
fi

# ==============================================================================
# 4. CADDYFILE — proxy inverso TRANSPARENTE de TODO Home Assistant. Sin go2rtc, sin
#    certificado autofirmado: unica responsabilidad de este add-on es dar un contexto seguro
#    (secure context) real al origen que sirve el dashboard completo de HA, incluida cualquier
#    card personalizada que necesite getUserMedia() (p.ej. islautopia-intercom-card).
# ==============================================================================
cat << EOF > "$CADDYFILE"
{
    admin off
    auto_https disable_redirects
}

:8443 {
    tls ${CERT_FILE} ${KEY_FILE}
    reverse_proxy homeassistant:8123
}
EOF

# ==============================================================================
# 5. ARRANQUE
# ==============================================================================
echo ""
echo "=================================================================="
echo " Islautopia HTTPS for Home Assistant esta funcionando"
echo "=================================================================="
echo " Accede a Home Assistant de forma segura (certificado real) en:"
print_highlighted_url "https://${HOSTNAME_PUBLIC}:8443"
echo " Configurala en Ajustes -> Sistema -> Red -> URL de Home Assistant"
echo " para que el resto de HA (enlaces, notificaciones, la app movil)"
echo " la use automaticamente."
echo " Este hostname resuelve SIEMPRE a tu IP local - no expone tu HA"
echo " fuera de tu red. Ver la seccion 'Seguridad y privacidad' del"
echo " README de este add-on para el detalle completo."
echo "=================================================================="
echo ""

caddy_pid=""

start_caddy() {
    caddy run --config "$CADDYFILE" --adapter caddyfile &
    caddy_pid=$!
}

restart_caddy() {
    if [ -n "$caddy_pid" ] && kill -0 "$caddy_pid" 2>/dev/null; then
        kill "$caddy_pid" 2>/dev/null
        wait "$caddy_pid" 2>/dev/null
    fi
    start_caddy
}

# Apagado limpio si el Supervisor para el add-on (SIGTERM).
trap 'echo "Deteniendo..."; [ -n "$caddy_pid" ] && kill "$caddy_pid" 2>/dev/null; exit 0' TERM INT

start_caddy

# ==============================================================================
# 6. BUCLE DE FONDO — reporta cambios de IP y recoge renovaciones de certificado. Este bucle
#    ES el proceso PID 1 del contenedor (Caddy corre como hijo en background) para poder
#    reiniciar Caddy sin depender de su API admin (deliberadamente desactivada arriba,
#    "admin off" - reducir superficie de ataque en un proxy que da acceso a toda la instancia
#    de HA).
# ==============================================================================
while true; do
    sleep 300   # 5 min - suficiente para detectar un cambio de IP (DHCP) sin martillear el Supervisor/VPS

    report_ip_if_changed

    # El cron de acme.sh en el VPS gestiona la renovacion real del certificado; aqui solo
    # volvemos a preguntar de vez en cuando (~12h) y comparamos el hash - ver fetch_cert().
    now=$(date +%s)
    last_check=0
    [ -f "$LAST_CERT_CHECK_FILE" ] && last_check=$(cat "$LAST_CERT_CHECK_FILE")

    if [ $((now - last_check)) -ge 43200 ]; then
        if fetch_cert; then
            echo "Certificado renovado - reiniciando Caddy para recogerlo..."
            restart_caddy
        fi
        echo "$now" > "$LAST_CERT_CHECK_FILE"
    fi

    # Vigilancia basica: si Caddy hubiera muerto por cualquier motivo, relanzarlo.
    if ! kill -0 "$caddy_pid" 2>/dev/null; then
        echo "Caddy no esta corriendo - reiniciando..."
        start_caddy
    fi
done
