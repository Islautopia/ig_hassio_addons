# Islautopia HTTPS for Home Assistant

**A real HTTPS certificate for your whole Home Assistant instance — zero configuration, no
domain, no DNS account, no port forwarding.**

> **Not a Nabu Casa alternative.** This add-on gives you no remote access to Home Assistant at
> all — the public hostname it uses only ever resolves to your local IP, unreachable from outside
> your network (see "Controlled risks" below). It solves a narrower, different problem: real
> HTTPS for your local access. For genuine remote access, use
> [Nabu Casa](https://www.nabucasa.com/) or your own remote-access proxy — no overlap, no
> conflict using both together.

---

## 1. What it is

A Supervisor add-on that puts a real, browser-trusted Let's Encrypt certificate in front of your
entire Home Assistant dashboard (port 8443), using the same DNS-01/Route53 automation that already
issues certificates for Islautopia Doorbell hardware. Separate from the legacy **Islautopia
Intercom Engine** add-on — no video/audio opinion, no `go2rtc`, no self-signed certificate. Its
only job is real HTTPS for Home Assistant as a whole.

## 2. What it's for

Browsers require a *secure context* (HTTPS) on the page that's actually loading before they allow
microphone access (`getUserMedia()`) — a doorbell's own certificate doesn't help with that, only
your Home Assistant origin's own certificate does. Built for the Islautopia Intercom Card, but
useful for **any** card or integration that needs the microphone, including third-party
RTSP/`go2rtc` setups — we share it as open Home Assistant infrastructure, not limited to
Islautopia hardware.

## 3. How it works internally

1. **Identity** (first run only): registers an anonymous identity with Islautopia's cloud
   (`POST /ha_instance/register`), stores the secret in the add-on's own persistent storage.
2. **DNS**: detects your HA host's local IP via the Supervisor's network API and reports it, which
   updates `<your-instance-id>.ha.doorbell.islautopia.com` → *your local IP*. Re-checked every 5
   minutes in the background.
3. **Certificate**: requests a real certificate for that hostname (DNS-01, works with no inbound
   internet reachability needed) and serves it locally via Caddy on port 8443, transparently
   proxying to Home Assistant Core. Re-checked for renewal roughly every 12 hours.

**The Islautopia VPS is never in the path of your actual Home Assistant traffic** — only used for
the occasional, background registration/DNS/certificate calls above. Once cached, your browser
talks directly to the add-on on your own LAN; your dashboard's live traffic never reaches
Islautopia's servers.

## 4. Controlled risks

1. **The public hostname always points at your LOCAL IP, never a public one.** It does **not**
   make Home Assistant reachable from outside your network — nobody outside your LAN can connect,
   even knowing the hostname.
2. **The hostname-to-local-IP association is a public DNS record.** Someone who guessed your
   `ha_instance_id` (16 random hex chars, practically unguessable) could see your local IP via
   DNS — that alone grants no access; reaching it still requires being on your LAN and passing
   your normal HA login.
3. **The certificate/private key are generated on Islautopia's server** (same mechanism as the
   doorbell itself) and delivered encrypted. If you'd rather your key never leave your network,
   use Home Assistant's own official "Let's Encrypt" add-on instead (requires your own domain +
   DNS provider credentials).
4. **Does NOT replace Home Assistant's own login** — only adds transport encryption, no change to
   authentication.
5. **Uninstalling stops it cleanly** — the DNS record just stops updating, normal local HTTP
   access keeps working.
6. **Not remote access** — see the callout at the top; use Nabu Casa or your own solution for that.

## 5. Required configuration

**The add-on itself needs zero configuration** — no options, no YAML. Install, start, done: a
Home Assistant instance has no factory identity the way a doorbell does, so there's nothing
meaningful to ask you for.

**One manual step is genuinely on you, stated explicitly rather than implied away**: the add-on
cannot change your existing bookmarks or "Home Assistant URL" setting by itself. After starting:

1. Check the **Log** tab for the printed hostname (e.g.
   `https://a1b2c3d4e5f60718.ha.doorbell.islautopia.com:8443`) — first request can take tens of
   seconds (real ACME issuance), later starts are instant.
2. Navigate to it yourself at least once.
3. *(Optional, recommended)* Set it as your **Home Assistant URL** under
   **Settings → System → Network** so the rest of HA uses it automatically.

## Troubleshooting

* **Add-on won't start / registration error:** check outbound internet access from your HA host.
* **Certificate not updating after an IP change:** wait up to 5 minutes, or restart the add-on.
* **Browser still blocks the microphone:** confirm you're using the
  `https://<id>.ha.doorbell.islautopia.com:8443` hostname, not the old `http://` address.
