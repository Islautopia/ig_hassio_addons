# Islautopia HTTPS for Home Assistant

**A real HTTPS certificate for your whole Home Assistant instance — zero configuration, no domain, no DNS account, no port forwarding.**

---

> **This is not a Nabu Casa alternative, and it does not compete with it.** This add-on gives you
> no remote access to Home Assistant whatsoever — the public hostname it uses only ever resolves
> to your **local** IP address, which is unreachable from outside your network by design (see
> "Controlled risks" below). It solves a different, much narrower problem: real HTTPS for your
> **local** access, which two-way audio needs. If you want genuine remote access to your Home
> Assistant instance, [Nabu Casa](https://www.nabucasa.com/) (or your own remote-access proxy)
> remains the right tool for that — there is no overlap between the two, and you can use both at
> the same time with no conflict.

## 1. What it is

A Home Assistant Supervisor add-on that obtains a real, browser-trusted Let's Encrypt certificate
for your Home Assistant instance and serves the whole dashboard behind it on port 8443 — using the
same DNS-01/Route53 automation that already issues certificates for Islautopia Doorbell hardware.
It's a clean, separate piece from the legacy [Islautopia Intercom Engine](../islautopia_intercom)
add-on (being deprecated for Islautopia hardware, kept only as a generic RTSP/`go2rtc` gateway for
third-party intercoms) — this new add-on bundles no `go2rtc`, generates no self-signed
certificate, and has no opinion about video/audio streams at all. Its only job is real HTTPS for
Home Assistant as a whole.

## 2. What it's for

Modern browsers require a *secure context* (HTTPS) on the page that's actually loading — not on
some other device it talks to — before they'll allow microphone access (`getUserMedia()`). If your
Home Assistant dashboard itself is served over plain `http://192.168...`, two-way audio in any
card that needs the microphone will be blocked by the browser, no matter how secure the device on
the other end is.

**We built this for the [Islautopia Intercom Card](https://github.com/Islautopia/islautopia-intercom-card),
but it isn't limited to it.** Anything that needs your Home Assistant *origin itself* to be a
secure context benefits — including third-party RTSP/`go2rtc`-based intercom or camera cards, or
any other integration that calls `getUserMedia()`. We're sharing it as an open piece of Home
Assistant infrastructure with the community, the same spirit the legacy add-on already had when
it advertised itself as compatible with "any RTSP/`go2rtc` setup," not just Islautopia hardware.

You never touch a domain registrar, a DNS provider account, or a router's port forwarding
settings. That's the entire value proposition versus Home Assistant's own official "Let's
Encrypt" add-on, which requires you to own a domain and hold credentials for a supported DNS
provider.

## 3. How it works internally

```
                         (only for: registration, IP updates, certificate issuance/renewal
                          — NEVER in the path of your actual HA traffic)
      ┌────────────────────────────────────────────────────────────────┐
      │                                                                │
      │                     Islautopia VPS (relay.doorbell.islautopia.com)
      │                     - issues/renews the Let's Encrypt cert (DNS-01)
      │                     - updates <id>.ha.doorbell.islautopia.com -> your local IP
      │                                                                │
      └───────────────────────────▲────────────────────────────────────┘
                                   │ HTTPS (register / report_ip / cert)
                                   │ occasional, background only
                                   │
   ┌───────────────────────────────────────────────────────────────────────┐
   │  Your home network (LAN)                                              │
   │                                                                       │
   │   Your browser/phone  ──HTTPS:8443 (real cert)──▶  This add-on        │
   │   (must be on your LAN                             (Caddy, on your    │
   │    to reach this)                                  HA host)          │
   │                                                          │            │
   │                                                          │ plain HTTP,│
   │                                                          │ localhost/ │
   │                                                          │ internal   │
   │                                                          │ Docker     │
   │                                                          │ network    │
   │                                                          ▼            │
   │                                                  Home Assistant Core  │
   │                                                  (homeassistant:8123) │
   └───────────────────────────────────────────────────────────────────────┘
```

Three things happen, in order, every time the add-on starts:

1. **Identity** — on first run only, it registers a brand-new, anonymous identity with
   Islautopia's cloud (`POST /ha_instance/register`) and stores the resulting secret in its own
   persistent storage. Every later run reuses that same stored identity.
2. **DNS** — it asks the Supervisor for your Home Assistant host's current local IP (same
   technique already used by the legacy add-on) and reports it to the cloud, which updates the DNS
   record `<your-instance-id>.ha.doorbell.islautopia.com` → *your local IP*. It keeps checking
   every 5 minutes in the background and re-reports only if the IP actually changed.
3. **Certificate** — it requests a real certificate for that hostname (issued via DNS-01, so it
   works even though nothing about your network is reachable from the internet) and serves it
   locally on port 8443 via Caddy, transparently reverse-proxying everything to Home Assistant
   Core underneath. It re-checks for renewals roughly every 12 hours.

**The Islautopia VPS is never in the path of your actual Home Assistant traffic.** Once the
certificate is issued and cached locally, your browser talks directly, on your own LAN, to the
add-on running right next to Home Assistant Core — nothing about your dashboard's live traffic
(states, camera streams, audio, logins) ever goes anywhere near Islautopia's servers.

## 4. Controlled risks

Read this before installing. These points are precise on purpose — please don't skim them.

1. **The public hostname always points at your LOCAL IP, never a public one.**
   `<your-instance-id>.ha.doorbell.islautopia.com` resolves to the private IP address of your
   Home Assistant host on your own network (e.g. `192.168.1.50`). This does **not** make your
   Home Assistant reachable from outside your network, and that is not its purpose — it exists
   purely to give your browser a hostname with a real, valid certificate to connect to. Nobody
   outside your LAN can connect to it, even knowing the hostname.

2. **That hostname-to-local-IP association is a public DNS record, like any other.** Anyone who
   knew or guessed your `ha_instance_id` (16 random hex characters — practically impossible to
   guess) could look up, via DNS, the *local* IP address of your home network (e.g.
   `192.168.1.50`). That alone does not grant any access to your Home Assistant — it only reveals
   an address, and reaching it still requires being physically on your LAN, in addition to passing
   your normal Home Assistant login.

3. **The certificate and its private key are generated on Islautopia's own server** (the same
   mechanism already used for Islautopia Doorbell hardware itself) and delivered to the add-on
   over an encrypted connection. Islautopia's infrastructure briefly handles that private key
   during issuance, the same as any provider that manages HTTPS on your behalf. If you'd rather
   your private key never leave your own network, the alternative is Home Assistant's own
   official **"Let's Encrypt"** add-on, which requires you to own a domain and hold credentials
   for a supported DNS provider yourself.

4. **This does NOT replace Home Assistant's own login.** It only adds real transport encryption
   (HTTPS) to the connection between your browser and your HA instance — it does not change or
   relax your existing authentication in any way. Anyone reaching the hostname still has to log in
   to Home Assistant normally.

5. **Uninstalling the add-on at any time is enough to stop using it.** The DNS record simply stops
   being updated (it keeps pointing at the last known IP until it naturally expires) and your
   normal local HTTP access to Home Assistant keeps working exactly as before — nothing else
   changes on your instance.

6. **This is not remote access, and it's not trying to be.** See the callout near the top of this
   README — if you want to reach your Home Assistant from outside your own network, use
   [Nabu Casa](https://www.nabucasa.com/) or your own remote-access solution; this add-on doesn't
   do that and isn't a substitute for it.

## 5. Required configuration

**The add-on itself needs zero configuration** — no options, no YAML, no fields to fill in. That's
deliberate: unlike an Islautopia Doorbell, a Home Assistant instance has no factory identity (no
MAC address), so there is nothing meaningful to ask you for. Install, start, done.

That said, to be precise rather than imply something that isn't 100% true: **there is one manual
step that's on you, not the add-on** — actually browsing to the new address. Installing and
starting the add-on does not change any bookmark, browser history, or existing "Home Assistant
URL" setting by itself; you need to:

1. Check the **Log** tab after starting, for a line like:
   `https://a1b2c3d4e5f60718.ha.doorbell.islautopia.com:8443`. The very first certificate request
   can take tens of seconds (a real ACME issuance happens on Islautopia's server) — every
   subsequent start is instant.
2. Navigate to that URL yourself at least once (and bookmark it, or tell your phone's HA app about
   it) — the add-on can't do this step for you.
3. *(Optional, recommended)* Set it under **Settings → System → Network → Home Assistant URL** so
   the rest of Home Assistant (links, notifications, mobile app discovery) starts using it
   automatically.

## 📥 Installation & Setup

1. **Add Repository** (skip if you already added it for the Intercom Engine):
   - **Settings → Add-ons → Add-on Store → ⋮ → Repositories** → add
     `https://github.com/Islautopia/ig_hassio_addons`.
2. Search for **"Islautopia HTTPS for Home Assistant"** and click **Install**, then **Start**.
3. Follow "Required configuration" above.

## ❓ Troubleshooting

* **Add-on won't start / registration error in the log:** check that your Home Assistant host has
  outbound internet access (needed to reach Islautopia's cloud for registration and certificate
  issuance).
* **Certificate not updating after a router/IP change:** the add-on re-checks its local IP every
  5 minutes — give it a few minutes, or restart the add-on to force an immediate check.
* **Browser still blocks the microphone:** make sure you're actually accessing Home Assistant via
  the `https://<id>.ha.doorbell.islautopia.com:8443` hostname printed in the add-on's log, not
  the old `http://` address (see "Required configuration" above).

---

**Developed by Islautopia Garage.**
*Questions or partnership inquiries? Contact us at: [garage@islautopia.com](mailto:garage@islautopia.com)*
