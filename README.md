# Islautopia Add-ons for Home Assistant

The official add-on repository for **Islautopia Garage**. Local-first, privacy-first, no
third-party cloud subscription required.

## Available add-ons

### [Islautopia HTTPS for Home Assistant](./islautopia_ha_https)

Real HTTPS for your **whole** Home Assistant instance — no domain, no DNS account, no port
forwarding, and it keeps working with no internet at all.

It exists because of a browser rule that nothing else can work around: a page served over plain
`http://` is not a *secure context*, and browsers refuse microphone access there. So two-way audio
in any dashboard card is impossible until Home Assistant **itself** is served over HTTPS. The
certificate on a doorbell cannot fix this — that certificate secures the connection *to the
doorbell*, not the origin serving your dashboard.

Two independent paths, both on port 8443 at once, each browser automatically getting whichever one
matches how it connected:

| path | what it needs | what it gives |
|---|---|---|
| **Public hostname** | a name lookup, so an internet connection | a real Let's Encrypt certificate, nothing to install on any device |
| **Local certificate authority** | nothing at all | HTTPS on bare LAN addresses, once you install its root on a device |

**Not a Nabu Casa alternative.** It gives no remote access whatsoever — only real local HTTPS.
Read the add-on's own "Security and privacy" section before installing.

## Installation

1. **Settings → Add-ons → Add-on Store**.
2. Three dots, top right → **Repositories**.
3. Add `https://github.com/Islautopia/ig_hassio_addons`, then close.
4. The add-on appears in the store. Install it, start it, and follow its log.

> **Install it from this repository, not as a local add-on.** A local add-on — a folder copied into
> the `addons` share — never updates: Home Assistant has no repository to pull from, so "check for
> updates" has nothing to check. Installed from here, it updates like any other add-on.

## If you own an Islautopia Doorbell

You want the [integration](https://github.com/Islautopia/islautopia-doorbell-integration) and the
[card](https://github.com/Islautopia/islautopia-intercom-card), both via HACS. This add-on is
independent of them — it solves the HTTPS problem for Home Assistant as a whole, and is worth
having whether or not you own our hardware.
