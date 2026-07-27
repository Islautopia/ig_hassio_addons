#!/bin/bash
set -u

# ==============================================================================
# Islautopia HTTPS for Home Assistant
#
# Serves the whole Home Assistant dashboard over HTTPS on port 8443, with TWO
# certificates picked per-connection by SNI:
#
#   1. A real Let's Encrypt certificate for <instance>.ha.doorbell.islautopia.com,
#      issued in the cloud over DNS-01. Zero friction -- every browser trusts it
#      out of the box -- but that hostname needs public DNS to resolve, so it is
#      useless exactly when the internet is down.
#
#   2. A certificate issued by a private CA generated on this machine, valid for
#      this host's LAN IP addresses plus homeassistant.local and localhost. Works
#      with no internet at all, but every device that wants it has to install the
#      CA root once.
#
# Both are served on the same port at the same time, so installing the root is
# OPTIONAL: it buys the guarantee that two-way audio keeps working during an
# internet outage, and nothing else.
#
# LANGUAGE: everything printed here is read by whoever installs the app, looking
# at a log, so it is English by project policy. Localized surfaces are the ones a
# homeowner sees; this is not one of them.
# ==============================================================================

# ==============================================================================
# 0. PATHS & CONSTANTS
# ==============================================================================
DATA_DIR="/data"
IDENTITY_FILE="$DATA_DIR/ha_instance.json"

# --- Let's Encrypt certificate (public hostname path) -------------------------
CERT_DIR="$DATA_DIR/certs"
CERT_FILE="$CERT_DIR/fullchain.pem"
KEY_FILE="$CERT_DIR/privkey.pem"
HASH_FILE="$CERT_DIR/cert.hash"

# --- Private CA (offline path) ------------------------------------------------
CA_DIR="$DATA_DIR/ca"
CA_CERT="$CA_DIR/ca.crt"
CA_KEY="$CA_DIR/ca.key"
LEAF_CERT="$CA_DIR/local.crt"
LEAF_KEY="$CA_DIR/local.key"
LEAF_CHAIN="$CA_DIR/local-fullchain.crt"
LEAF_SAN_FILE="$CA_DIR/local.san"      # the SAN list the current leaf was issued for

# The portal directory holds ONLY the public CA certificate. The CA private key
# lives in $CA_DIR and never inside a directory a file_server is pointed at --
# defence in depth on top of the exact-path matchers in the Caddyfile.
PORTAL_DIR="/var/lib/islautopia-portal"

LAST_IP_FILE="$DATA_DIR/last_ip"
LAST_CERT_CHECK_FILE="$DATA_DIR/last_cert_check"
CADDYFILE="/etc/Caddyfile"

HTTPS_PORT=8443
PORTAL_PORT=8099

# Root CA lifetime is long on purpose: it is the one artefact a human installs by
# hand on every device, so it must not come back to bother them. The leaf is short
# by comparison and renews itself unattended. That asymmetry is the whole reason
# this app issues from a CA instead of shipping a standalone self-signed cert.
CA_DAYS=3650
LEAF_DAYS=398                          # under the 398-day cap Apple/Chrome apply to server certs
LEAF_RENEW_BEFORE=$((30 * 24 * 3600))

# Confirmed 2026-07-09: same host the doorbell itself uses for /register
# (main/cloud_client.c::RELAY_HOST in IG_Doorbell).
API_BASE="https://relay.doorbell.islautopia.com"
DOMAIN_SUFFIX="ha.doorbell.islautopia.com"

mkdir -p "$CERT_DIR" "$CA_DIR" "$PORTAL_DIR"
chmod 700 "$CA_DIR"

ha_instance_id=""
ha_secret=""
HOSTNAME_PUBLIC=""
PRIMARY_IP="homeassistant.local"

# ==============================================================================
# COLOR / HYPERLINK HELPERS
#
# ANSI colour (CSI, ESC[...m) renders correctly in the Home Assistant Supervisor
# log viewer (confirmed -- other apps in the ecosystem already use it).
#
# The hyperlink wrapper uses OSC 8 (ESC]8;;URL ST TEXT ESC]8;;ST) to try to make
# URLs clickable in viewers that support it (same trick as `ls --hyperlink`). NOT
# verified against the real Supervisor log viewer. Low risk either way: a properly
# terminated OSC sequence is swallowed silently by viewers that do not understand
# it, and the visible text -- the URL itself -- still shows normally. If the HA
# viewer is ever confirmed to print raw escape bytes, drop the OSC 8 wrapper from
# print_highlighted_url() and keep only the colour.
#
# ESC bytes are built with ANSI-C quoting ($'\033', interpreted by the shell as it
# parses this script) rather than left as literal "\033" for printf to expand at
# runtime. A first attempt with printf proved fragile: several consecutive "\033"
# sequences in one format string, with a "\\" (the ST terminator) among them, did
# NOT all expand -- verified with `cat -A`, literal "\033[0m" survived into the
# output. With $'\033' the ESC byte exists before printf ever sees it.
# ==============================================================================
ESC=$'\033'
readonly ESC
readonly ANSI_RESET="${ESC}[0m"
readonly ANSI_BOLD_CYAN="${ESC}[1;36m"
readonly ANSI_BOLD_YELLOW="${ESC}[1;33m"

print_highlighted_url() {
    local url="$1"
    local osc8_start="${ESC}]8;;${url}${ESC}\\"
    local osc8_end="${ESC}]8;;${ESC}\\"
    printf '%s%s%s%s%s\n' "$ANSI_BOLD_CYAN" "$osc8_start" "$url" "$osc8_end" "$ANSI_RESET"
}

print_highlighted() {
    printf '%s%s%s\n' "$ANSI_BOLD_YELLOW" "$1" "$ANSI_RESET"
}

# ==============================================================================
# 1. LOCAL NETWORK ADDRESSES
#
# Asks the Supervisor for the HOST's interfaces, not this container's. That
# distinction matters: this container sits on Home Assistant's internal Docker
# network (172.30.32.x), so reading its own interfaces would yield addresses no
# browser on the LAN can reach.
#
# Every host IPv4 is collected, not just the primary one: a Home Assistant host
# with more than one interface (several VLANs, wired plus wireless) is reachable
# at any of them, and the certificate has to be valid for whichever address the
# user actually types.
# ==============================================================================
supervisor_network_info() {
    curl -s -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        --max-time 10 http://supervisor/network/info
}

detect_primary_ip() {
    supervisor_network_info \
        | jq --raw-output '.data.interfaces[]? | select(.primary==true) | .ipv4.address[0]? // empty' 2>/dev/null \
        | cut -d'/' -f1 | head -n1
}

detect_all_ips() {
    supervisor_network_info \
        | jq --raw-output '.data.interfaces[]? | .ipv4.address[]? // empty' 2>/dev/null \
        | cut -d'/' -f1 \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
        | grep -v '^127\.' \
        | sort -u
}

refresh_primary_ip() {
    local ip
    ip=$(detect_primary_ip)
    if [ -z "$ip" ]; then
        # Prefer any numeric address over a .local name, which does not cross
        # network segments (see the portal text for why that matters here).
        ip=$(detect_all_ips | head -n1)
    fi
    if [ -n "$ip" ]; then
        PRIMARY_IP="$ip"
    else
        PRIMARY_IP="homeassistant.local"
    fi
}

# ==============================================================================
# 2. PRIVATE CA -- created exactly once, then never touched again
#
# Regenerating the root would silently invalidate every device that already trusts
# it, so it is created only when absent and nothing here ever rewrites it. This is
# precisely the trap a single self-signed certificate falls into: it has to avoid
# being regenerated in order to keep devices trusting it, which means nothing
# about it can ever change either -- not its expiry, not the addresses it covers.
#
# The root signs leaves directly, with no intermediate. An intermediate would add
# no real security: both keys would sit side by side in the same private volume,
# so whatever could steal one could steal the other. Same call mkcert makes.
# ==============================================================================
ca_fingerprint() {
    openssl x509 -in "$CA_CERT" -noout -fingerprint -sha256 2>/dev/null \
        | sed 's/^.*Fingerprint=//'
}

ca_subject() {
    openssl x509 -in "$CA_CERT" -noout -subject 2>/dev/null | sed 's/^subject=[[:space:]]*//'
}

ensure_ca() {
    if [ -f "$CA_CERT" ] && [ -f "$CA_KEY" ]; then
        return 0
    fi

    echo "No private certificate authority yet - creating one (this happens exactly once)..."

    if ! openssl genrsa -out "$CA_KEY" 2048 2>/dev/null; then
        echo "FATAL: could not generate the CA private key."
        return 1
    fi
    chmod 600 "$CA_KEY"

    # A short stable suffix keeps two Home Assistant instances apart in a phone's
    # certificate list. Derived from the CA key itself so it exists even on a first
    # boot with no internet, where there is no cloud identity to name it after.
    local suffix
    suffix=$(openssl rsa -in "$CA_KEY" -pubout 2>/dev/null | sha256sum | cut -c1-8)

    cat > "$CA_DIR/ca.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = Islautopia Home Assistant Local CA ${suffix}
O  = Islautopia
[v3_ca]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
EOF

    if ! openssl req -x509 -new -key "$CA_KEY" -days "$CA_DAYS" -sha256 \
            -out "$CA_CERT" -config "$CA_DIR/ca.cnf" -extensions v3_ca 2>/dev/null; then
        echo "FATAL: could not create the CA certificate."
        return 1
    fi

    echo "Created: Islautopia Home Assistant Local CA ${suffix} (valid for ${CA_DAYS} days)"
    return 0
}

# ==============================================================================
# 3. LEAF CERTIFICATE -- reissued automatically whenever it needs to be
#
# Reissued when the address list changes or when it approaches expiry. Neither
# event requires anyone to touch a phone: devices trust the CA, not the leaf.
# ==============================================================================
build_san_string() {
    local san="DNS:homeassistant.local,DNS:localhost,IP:127.0.0.1"
    local ip
    for ip in $(detect_all_ips); do
        san="${san},IP:${ip}"
    done
    echo "$san"
}

leaf_needs_reissue() {
    local want_san="$1"

    if [ ! -f "$LEAF_CERT" ] || [ ! -f "$LEAF_KEY" ]; then
        echo "none issued yet"
        return 0
    fi

    local have_san=""
    [ -f "$LEAF_SAN_FILE" ] && have_san=$(cat "$LEAF_SAN_FILE")
    if [ "$want_san" != "$have_san" ]; then
        echo "this host's addresses changed"
        return 0
    fi

    if ! openssl x509 -in "$LEAF_CERT" -noout -checkend "$LEAF_RENEW_BEFORE" >/dev/null 2>&1; then
        echo "expires within 30 days"
        return 0
    fi

    return 1
}

issue_leaf() {
    local san="$1"
    local cn="$2"

    if ! openssl req -new -newkey rsa:2048 -nodes \
            -keyout "$LEAF_KEY" -out "$CA_DIR/local.csr" \
            -subj "/CN=${cn}" 2>/dev/null; then
        return 1
    fi
    chmod 600 "$LEAF_KEY"

    cat > "$CA_DIR/local.ext" <<EOF
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = ${san}
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

    if ! openssl x509 -req -in "$CA_DIR/local.csr" \
            -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
            -out "$LEAF_CERT" -days "$LEAF_DAYS" -sha256 \
            -extfile "$CA_DIR/local.ext" 2>/dev/null; then
        return 1
    fi

    # Serve leaf + root. A client that already trusts the root does not need it
    # sent, but including it costs one small record and helps lenient clients.
    cat "$LEAF_CERT" "$CA_CERT" > "$LEAF_CHAIN"
    echo "$san" > "$LEAF_SAN_FILE"
    rm -f "$CA_DIR/local.csr"
    return 0
}

# Returns 0 when the certificate changed, 1 when untouched, 2 on failure.
ensure_leaf() {
    local san reason
    san=$(build_san_string)

    if reason=$(leaf_needs_reissue "$san"); then
        echo "Issuing the local certificate (${reason})..."
        if issue_leaf "$san" "$PRIMARY_IP"; then
            echo "Local certificate valid for: ${san}"
            return 0
        fi
        echo "WARNING: could not issue the local certificate."
        return 2
    fi

    return 1
}

# ==============================================================================
# 4. CLOUD IDENTITY -- optional, and explicitly allowed to fail
#
# A Home Assistant instance has no factory identity the way a doorbell does, so
# POST /ha_instance/register always mints a NEW one. It is stored in /data and
# only requested when that file is absent.
#
# Failure here is NOT fatal, and that is a deliberate correction: it used to be
# `exit 1`, which meant a first install with no internet left the user with
# nothing at all -- the exact opposite of what this app is for.
# ==============================================================================
ensure_identity() {
    if [ -f "$IDENTITY_FILE" ]; then
        ha_instance_id=$(jq --raw-output '.ha_instance_id // empty' "$IDENTITY_FILE" 2>/dev/null)
        ha_secret=$(jq --raw-output '.ha_secret // empty' "$IDENTITY_FILE" 2>/dev/null)
        if [ -n "$ha_instance_id" ]; then
            HOSTNAME_PUBLIC="${ha_instance_id}.${DOMAIN_SUFFIX}"
            return 0
        fi
        return 1
    fi

    echo "No cloud identity yet - registering this Home Assistant instance..."
    local response id secret
    response=$(curl -sS -X POST "$API_BASE/ha_instance/register" --max-time 30 2>&1)
    id=$(echo "$response" | jq --raw-output '.ha_instance_id // empty' 2>/dev/null)
    secret=$(echo "$response" | jq --raw-output '.ha_secret // empty' 2>/dev/null)

    if [ -z "$id" ] || [ -z "$secret" ]; then
        echo "Could not reach the cloud to register (no internet, or the service is down)."
        echo "  Response: $response"
        echo "  Not fatal: the local certificate needs no internet whatsoever, and"
        echo "  registration is retried automatically in the background."
        return 1
    fi

    printf '{"ha_instance_id":"%s","ha_secret":"%s"}' "$id" "$secret" > "$IDENTITY_FILE"
    chmod 600 "$IDENTITY_FILE"
    ha_instance_id="$id"
    ha_secret="$secret"
    HOSTNAME_PUBLIC="${ha_instance_id}.${DOMAIN_SUFFIX}"
    echo "Registered a new cloud identity: $ha_instance_id"
    return 0
}

report_ip_if_changed() {
    [ -n "$ha_instance_id" ] || return 0

    local ip last
    ip=$(detect_primary_ip)
    if [ -z "$ip" ]; then
        echo "Could not detect the local IP via the Supervisor - skipping the DNS update."
        return 0
    fi

    last=""
    [ -f "$LAST_IP_FILE" ] && last=$(cat "$LAST_IP_FILE")

    if [ "$ip" != "$last" ]; then
        echo "Local IP: $ip (previously: ${last:-none known}) - updating the DNS record..."
        if curl -sS -X POST "$API_BASE/ha_instance/${ha_instance_id}/report_ip" \
                -H "Authorization: Bearer ${ha_secret}" \
                -H "Content-Type: application/json" \
                -d "{\"ip\":\"${ip}\"}" \
                --max-time 15 -o /dev/null; then
            echo "$ip" > "$LAST_IP_FILE"
        else
            echo "Could not update the DNS record right now - will retry in the background."
        fi
    fi
}

# ==============================================================================
# 5. LET'S ENCRYPT CERTIFICATE -- also optional
#
# The first call can take tens of seconds (a real ACME issuance runs on the VPS);
# later calls return the cached certificate instantly. The hash is compared with
# what is already on disk before rewriting anything, the same way
# https_cert_task.c does in the doorbell firmware.
# ==============================================================================
fetch_cert() {
    [ -n "$ha_instance_id" ] || return 1

    echo "Requesting the public certificate for ${HOSTNAME_PUBLIC}..."
    local response new_hash old_hash
    response=$(curl -sS -X GET "$API_BASE/ha_instance/${ha_instance_id}/cert" \
        -H "Authorization: Bearer ${ha_secret}" --max-time 120 2>&1)

    new_hash=$(echo "$response" | jq --raw-output '.hash // empty' 2>/dev/null)
    if [ -z "$new_hash" ]; then
        echo "No valid certificate came back - keeping whatever is already cached."
        echo "  Response: $response"
        return 1
    fi

    old_hash=""
    [ -f "$HASH_FILE" ] && old_hash=$(cat "$HASH_FILE")

    if [ "$new_hash" = "$old_hash" ] && [ -s "$CERT_FILE" ] && [ -s "$KEY_FILE" ]; then
        echo "Public certificate unchanged (hash $new_hash)."
        return 1
    fi

    echo "$response" | jq --raw-output '.cert' > "$CERT_FILE"
    echo "$response" | jq --raw-output '.key' > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    echo "$new_hash" > "$HASH_FILE"
    echo "Public certificate updated (hash $new_hash)."
    return 0
}

have_public_cert() {
    [ -n "$HOSTNAME_PUBLIC" ] && [ -s "$CERT_FILE" ] && [ -s "$KEY_FILE" ]
}

# ==============================================================================
# 6. TRUST PORTAL -- the page that hands out the CA root
#
# Served over PLAIN HTTP on purpose. Asking someone to click through a browser's
# certificate warning in order to download the very certificate that removes that
# warning teaches exactly the habit this project wants to kill.
#
# The trade-off is stated on the page itself rather than hidden: plain HTTP means
# anyone already on the LAN could swap the file, so the authoritative fingerprint
# is the one this app prints in its log -- read through Home Assistant's own
# authenticated interface -- and the page tells the reader to compare the two
# before installing anything.
# ==============================================================================
write_portal() {
    cp "$CA_CERT" "$PORTAL_DIR/ca.crt"
    chmod 644 "$PORTAL_DIR/ca.crt"

    local fp ca_name
    fp=$(ca_fingerprint)
    ca_name=$(ca_subject)

    cat > "$PORTAL_DIR/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Islautopia - trust this Home Assistant</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body { margin:0; padding:24px 16px 64px; font:16px/1.6 system-ui,-apple-system,"Segoe UI",sans-serif;
         background:#f4f6f9; color:#1b1f24; }
  main { max-width:720px; margin:0 auto; }
  .card { background:#fff; border-radius:16px; padding:28px; margin-bottom:20px;
          box-shadow:0 2px 12px rgba(0,0,0,.06); }
  h1 { font-size:1.5rem; margin:0 0 6px; line-height:1.3; }
  h2 { font-size:1.15rem; margin:0 0 10px; }
  .sub { color:#5a6472; margin:0 0 18px; }
  a.btn { display:block; text-align:center; padding:16px 24px; background:#0b6bcb; color:#fff;
          text-decoration:none; border-radius:12px; font-weight:600; }
  code, .fp { font-family:ui-monospace,SFMono-Regular,Menlo,monospace; }
  .fp { display:block; word-break:break-all; background:#0f172a; color:#7dd3fc; padding:14px;
        border-radius:10px; font-size:.82rem; letter-spacing:.03em; margin:10px 0 0; }
  .warn { border-left:4px solid #d97706; background:#fffbeb; padding:14px 16px; border-radius:0 10px 10px 0; }
  .note { border-left:4px solid #0b6bcb; background:#eff6ff; padding:14px 16px; border-radius:0 10px 10px 0; }
  ol, ul { padding-left:22px; } li { margin:7px 0; }
  details { border-top:1px solid #e6e9ee; padding:14px 0; }
  details:last-of-type { border-bottom:1px solid #e6e9ee; }
  summary { cursor:pointer; font-weight:600; }
  .muted { color:#5a6472; font-size:.92rem; }
  @media (prefers-color-scheme: dark) {
    body { background:#0f1216; color:#e6e9ee; }
    .card { background:#171b21; box-shadow:none; }
    .sub,.muted { color:#9aa4b2; }
    .warn { background:#2a1f08; } .note { background:#0d1b2e; }
    details, details:last-of-type { border-color:#252b33; }
  }
</style>
</head>
<body>
<main>

<div class="card">
  <h1>Keep two-way audio working without internet</h1>
  <p class="sub">Optional. About a minute, once per device.</p>

  <p>Your browser only lets a page use the microphone over a <strong>secure
  connection</strong>. This Home Assistant already has one, vouched for by a public
  certificate authority &mdash; but the address that certificate was issued for has to be
  looked up on the internet. When your line is down, that address stops working, and the
  microphone goes with it.</p>

  <p>Installing the small file below fixes that for good. It tells this device to also
  trust certificates issued by <em>this Home Assistant itself</em>, so reaching it at its
  local address stays secure whether or not you have internet.</p>

  <div class="note">
    <strong>Do you actually need this?</strong> If your internet is reliable and you can
    live without the doorbell's audio during an outage, close this page and change nothing.
    Everything else already works.
  </div>
</div>

<div class="card">
  <h2>Step 1 &mdash; check the fingerprint</h2>
  <p>A <em>fingerprint</em> is a short code calculated from a file: same fingerprint, same
  file. Checking it is what stops someone else on your network from handing you their file
  instead of this one.</p>

  <p>This page claims the fingerprint is:</p>
  <span class="fp">${fp}</span>

  <div class="warn" style="margin-top:18px">
    <strong>Don't take this page's word for it.</strong> It is served over an ordinary
    unsecured connection, so that you don't have to click through a security warning just to
    fetch the file that removes security warnings &mdash; but that also means the value above
    could have been tampered with on the way to you. Compare it against the copy printed in
    the app's own log:
    <br><br>
    <strong>Settings &rarr; Apps &rarr; Islautopia HTTPS for Home Assistant &rarr; Log</strong>
    <br><br>
    That log reaches you through Home Assistant's own secure, logged-in interface, so it is
    the copy to trust. If the two match, this file is genuine.
    <strong>If they differ, stop and do not install it.</strong>
  </div>
</div>

<div class="card">
  <h2>Step 2 &mdash; download it</h2>
  <p><a class="btn" href="/ca.crt" download>Download the certificate</a></p>
  <p class="muted" style="margin-top:16px">Issued by: <code>${ca_name}</code></p>
</div>

<div class="card">
  <h2>Step 3 &mdash; install it</h2>
  <p>Pick your device. <strong>iPhone and iPad need two separate steps</strong> &mdash; the
  second is easy to miss, and skipping it looks exactly like the whole thing failing, with
  nothing on screen to tell you why.</p>

  <details open>
    <summary>iPhone / iPad</summary>
    <p><strong>Both parts are required.</strong> After the first, iOS says the profile is
    installed, which sounds finished. It isn't: iOS deliberately leaves a new certificate
    authority switched off until you turn it on yourself.</p>
    <p><em>Part one &mdash; install the profile</em></p>
    <ol>
      <li>Tap <strong>Download the certificate</strong> above in <strong>Safari</strong>
          (Chrome and Firefox on iOS cannot install profiles).</li>
      <li>Tap <strong>Allow</strong> when iOS offers to download a configuration profile.</li>
      <li>Open <strong>Settings</strong>. Near the top you'll see
          <strong>Profile Downloaded</strong> &mdash; tap it.</li>
      <li>Tap <strong>Install</strong> at the top right, enter your passcode, and confirm.</li>
    </ol>
    <p><em>Part two &mdash; switch it on. This is the step everyone misses.</em></p>
    <ol>
      <li>Go to <strong>Settings &rarr; General &rarr; About</strong>.</li>
      <li>Scroll all the way to the bottom and tap
          <strong>Certificate Trust Settings</strong>.</li>
      <li>Turn <strong>on</strong> the switch next to
          <strong>Islautopia Home Assistant Local CA</strong>.</li>
      <li>Confirm the warning iOS shows about what full trust means.</li>
    </ol>
    <p class="muted">No "Certificate Trust Settings" entry? Then part one didn't finish
    &mdash; go back and complete the profile installation first.</p>
  </details>

  <details>
    <summary>Android phone or tablet</summary>
    <ol>
      <li>Tap <strong>Download the certificate</strong> above.</li>
      <li>Open <strong>Settings</strong> and search for <strong>CA certificate</strong>. The
          exact path varies by manufacturer; on most devices it is <strong>Security &rarr;
          More security settings &rarr; Encryption &amp; credentials &rarr; Install a
          certificate &rarr; CA certificate</strong>.</li>
      <li>Tap <strong>Install anyway</strong> at the warning, then choose the downloaded
          <code>ca.crt</code>.</li>
    </ol>
    <p class="muted">Android will show a recurring "your network may be monitored" notice.
    That is its standard notice for any user-installed authority, not a sign of trouble.</p>
    <p class="muted">The Home Assistant companion app honours certificates installed this
    way. Firefox for Android does not &mdash; it keeps its own separate list.</p>
  </details>

  <details>
    <summary>Windows</summary>
    <ol>
      <li>Download the file, double-click it, and choose <strong>Install Certificate</strong>.</li>
      <li>Select <strong>Local Machine</strong> (needs administrator rights) and click
          <strong>Next</strong>.</li>
      <li>Choose <strong>Place all certificates in the following store</strong>, click
          <strong>Browse</strong>, and pick <strong>Trusted Root Certification
          Authorities</strong>.</li>
      <li>Click <strong>Next</strong>, then <strong>Finish</strong>, and accept the warning.</li>
      <li>Restart your browser.</li>
    </ol>
    <p class="muted">Chrome and Edge use this store. Firefox does not &mdash; see below.</p>
  </details>

  <details>
    <summary>macOS</summary>
    <ol>
      <li>Download the file and double-click it &mdash; <strong>Keychain Access</strong> opens.</li>
      <li>Add it to the <strong>System</strong> keychain, or <strong>login</strong> for just
          your own account.</li>
      <li>Find <strong>Islautopia Home Assistant Local CA</strong> in the list and
          double-click it.</li>
      <li>Expand <strong>Trust</strong> and set <strong>When using this certificate</strong>
          to <strong>Always Trust</strong>.</li>
      <li>Close the window and enter your password to save.</li>
    </ol>
  </details>

  <details>
    <summary>Firefox, on any operating system</summary>
    <p>Firefox ignores the operating system's certificate list and keeps its own, so this
    has to be done separately even if you already installed the file above.</p>
    <ol>
      <li>Open <strong>Settings &rarr; Privacy &amp; Security</strong>.</li>
      <li>Scroll to <strong>Certificates</strong> and click <strong>View Certificates</strong>.</li>
      <li>On the <strong>Authorities</strong> tab, click <strong>Import</strong> and pick the
          downloaded file.</li>
      <li>Tick <strong>Trust this CA to identify websites</strong> and click <strong>OK</strong>.</li>
    </ol>
  </details>
</div>

<div class="card">
  <h2>Step 4 &mdash; check it worked</h2>
  <p>On the device you just set up, open:</p>
  <p><a class="btn" href="https://${PRIMARY_IP}:${HTTPS_PORT}/">https://${PRIMARY_IP}:${HTTPS_PORT}/</a></p>
  <p>Home Assistant should load with no security warning at all. If your browser still
  complains, the certificate isn't trusted yet &mdash; on iPhone or iPad that almost always
  means part two above hasn't been done.</p>
  <p class="muted">Use this numeric address rather than <code>homeassistant.local</code>.
  Names ending in <code>.local</code> are resolved by a neighbour-discovery mechanism that
  does not travel between networks, so if your phone and your Home Assistant sit on
  different network segments &mdash; separate Wi-Fi networks, a guest network, anything with
  a router between them &mdash; the name simply won't resolve. The numeric address always
  will.</p>
</div>

<p class="muted" style="text-align:center">Islautopia Garage</p>
</main>
</body>
</html>
EOF
}

# ==============================================================================
# 7. CADDYFILE
#
# Two site blocks on :${HTTPS_PORT}, and Caddy picks between them by SNI -- the
# hostname the browser states at the very start of the connection:
#
#   <instance>.ha.doorbell.islautopia.com  -> the Let's Encrypt certificate
#   everything else (catch-all)            -> the certificate from our own CA
#
# The catch-all is what a browser hits when someone types a raw IP address,
# because connecting to an IP sends NO SNI at all. Verified with real handshakes
# against Caddy 2.10.0 (what Alpine ships) and 2.11.4: no SNI, and SNI for
# homeassistant.local, both land on the local certificate, while the public
# hostname lands on the public one.
#
# The public block is emitted ONLY when its certificate file actually exists.
# Caddy refuses to start at all if a referenced certificate file is missing
# ("loading tls app module: ... no such file"), which would take the offline path
# down along with it -- the exact opposite of the point of this app.
#
# `auto_https off` is essential: without it, naming a hostname in a site address
# makes Caddy try to obtain that certificate over ACME by itself. Confirmed off in
# the logs ("automatic HTTPS is completely disabled").
# ==============================================================================
write_caddyfile() {
    {
        cat <<EOF
{
	admin off
	auto_https off
}

(hass) {
	handle {
		reverse_proxy homeassistant:8123
	}
}

# Trust portal, plain HTTP. Serves the CA root and its instructions and nothing
# else -- deliberately no proxy to Home Assistant on this port.
:${PORTAL_PORT} {
	root * ${PORTAL_DIR}
	handle /ca.crt {
		header Content-Disposition "attachment; filename=islautopia-ha-ca.crt"
		header Content-Type "application/x-x509-ca-cert"
		file_server
	}
	handle {
		rewrite * /index.html
		file_server
	}
}
EOF

        if have_public_cert; then
            cat <<EOF

# Public hostname -> real Let's Encrypt certificate. Needs internet to resolve.
${HOSTNAME_PUBLIC}:${HTTPS_PORT} {
	tls ${CERT_FILE} ${KEY_FILE}
	import hass
}
EOF
        fi

        cat <<EOF

# Everything else -> our own CA: the no-SNI case (raw IP address), plus
# homeassistant.local and localhost. Needs no internet.
:${HTTPS_PORT} {
	tls ${LEAF_CHAIN} ${LEAF_KEY}
	handle /islautopia/ca.crt {
		root * ${PORTAL_DIR}
		rewrite * /ca.crt
		header Content-Disposition "attachment; filename=islautopia-ha-ca.crt"
		header Content-Type "application/x-x509-ca-cert"
		file_server
	}
	handle /islautopia/trust {
		root * ${PORTAL_DIR}
		rewrite * /index.html
		file_server
	}
	import hass
}
EOF
    } > "$CADDYFILE"
}

# ==============================================================================
# 8. START -- the local path comes first, on purpose
#
# The CA and the local certificate need no network at all, so they are built and
# served before anything is asked of the cloud. HTTPS is therefore up within a
# second of boot even on an instance with no internet, and the Let's Encrypt side
# folds in afterwards if and when it succeeds.
# ==============================================================================
refresh_primary_ip

if ! ensure_ca; then
    echo "FATAL: no private CA and none could be created - cannot serve HTTPS at all."
    exit 1
fi

ensure_leaf
if [ ! -s "$LEAF_CHAIN" ] || [ ! -s "$LEAF_KEY" ]; then
    echo "FATAL: no local certificate available - cannot serve HTTPS at all."
    exit 1
fi

write_portal
write_caddyfile

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

trap 'echo "Stopping..."; [ -n "$caddy_pid" ] && kill "$caddy_pid" 2>/dev/null; exit 0' TERM INT

start_caddy

echo ""
echo "=================================================================="
echo " Islautopia HTTPS for Home Assistant is running"
echo "=================================================================="
echo ""
echo " LOCAL ACCESS - works with or without internet:"
print_highlighted_url "https://${PRIMARY_IP}:${HTTPS_PORT}"
echo ""
echo " For that address to be trusted - no browser warning, microphone"
echo " allowed - each device installs one small file, once. Open this"
echo " page on the device and follow it:"
print_highlighted_url "http://${PRIMARY_IP}:${PORTAL_PORT}"
echo ""
echo " Certificate authority fingerprint (SHA-256). THIS log line is the"
echo " authoritative copy: compare it against the one shown on that page"
echo " before installing anything."
print_highlighted "   $(ca_fingerprint)"
echo ""
echo " Installing it is OPTIONAL. It buys exactly one thing: the"
echo " doorbell's two-way audio keeps working while your internet is down."
echo "=================================================================="
echo ""

# ==============================================================================
# 9. CLOUD PATH -- best effort, never blocks the local path
# ==============================================================================
ensure_identity
report_ip_if_changed
if fetch_cert; then
    echo "Public certificate ready - reloading to serve it alongside the local one."
    write_caddyfile
    restart_caddy
fi

if have_public_cert; then
    echo ""
    echo "=================================================================="
    echo " PUBLIC HOSTNAME - works while you have internet, no setup needed"
    echo "=================================================================="
    print_highlighted_url "https://${HOSTNAME_PUBLIC}:${HTTPS_PORT}"
    echo " Trusted by every browser out of the box. Set it under Settings ->"
    echo " System -> Network -> Home Assistant URL so the rest of Home"
    echo " Assistant uses it automatically."
    echo " This hostname always resolves to your LOCAL IP - it does not"
    echo " expose Home Assistant outside your network."
    echo "=================================================================="
    echo ""
else
    echo ""
    echo "NOTE: no public certificate is active, so the public hostname is"
    echo "      unavailable right now. The local address above is unaffected"
    echo "      and keeps working. This is retried in the background."
    echo ""
fi

# ==============================================================================
# 10. BACKGROUND LOOP
#
# This loop IS the container's PID 1 (Caddy runs as a background child) so Caddy
# can be restarted without its admin API, which is deliberately disabled above --
# smaller attack surface on a proxy that fronts an entire Home Assistant instance.
# Restarting is also the only way to pick up a renewed certificate, since Caddy
# reads certificate files once at config load and does not watch them for changes.
# ==============================================================================
while true; do
    sleep 300

    caddy_needs_restart=0

    # The local path goes first: it is the one that must never depend on the network.
    refresh_primary_ip
    if ensure_leaf; then
        write_portal
        caddy_needs_restart=1
    fi

    # Pick up a cloud identity if we never managed to get one (first boot offline).
    if [ -z "$ha_instance_id" ] && ensure_identity; then
        caddy_needs_restart=1
    fi

    report_ip_if_changed

    now=$(date +%s)
    last_check=0
    [ -f "$LAST_CERT_CHECK_FILE" ] && last_check=$(cat "$LAST_CERT_CHECK_FILE")

    if [ $((now - last_check)) -ge 43200 ]; then
        if fetch_cert; then
            echo "Public certificate renewed."
            caddy_needs_restart=1
        fi
        echo "$now" > "$LAST_CERT_CHECK_FILE"
    fi

    if [ "$caddy_needs_restart" -eq 1 ]; then
        echo "Configuration changed - restarting the HTTPS server to pick it up..."
        write_caddyfile
        restart_caddy
    elif ! kill -0 "$caddy_pid" 2>/dev/null; then
        echo "HTTPS server is not running - restarting it..."
        start_caddy
    fi
done
