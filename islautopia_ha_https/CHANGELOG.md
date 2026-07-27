# Changelog

## 0.3.0

**Fixed: the app could not start at all without internet.** If the certificate fetch failed and
nothing was cached, it exited instead of starting. Separately, the HTTPS server itself refuses to
start when a referenced certificate file is missing, so an absent certificate took everything down
with it. A first install in a house with no line yet ended up with nothing at all — the exact
situation this app is meant to cover. The local path now comes up first and needs no network, and
everything involving the cloud degrades to a warning and retries in the background.

**New: HTTPS that keeps working with no internet.** The public hostname is only usable while its
name can be looked up online. This release adds a second, independent path: the app creates its own
small certificate authority on first run and issues itself a certificate for this host's local IP
addresses (plus `homeassistant.local` and `localhost`). Both certificates are now served on port
8443 at the same time, and each browser automatically receives whichever one matches how it
connected — bare IP addresses get the local one, the public hostname gets Let's Encrypt.

Install the authority's root on a device, once, and two-way audio keeps working there during an
internet outage. **It is optional**, and the existing zero-setup path is completely unchanged for
anyone who doesn't need the guarantee.

**New: trust portal on port 8099.** Serves the root certificate and step-by-step instructions for
iOS, Android, Windows, macOS and Firefox. iOS needs two separate steps and the second is easy to
miss, so it is called out explicitly. Deliberately plain HTTP, so you never have to click through a
certificate warning to fetch the certificate that removes warnings — with the authoritative
fingerprint printed in this app's log for you to compare against.

**Also:** certificates now cover *every* local address the host has, not just the primary one, so
Home Assistant hosts on several networks work at any of their addresses. Local certificates are
reissued automatically when those addresses change or as expiry approaches, with no device ever
needing to be touched again.

## 0.2.0

- Highlight the local access URL in the startup log: bold color, wrapped as an OSC 8 hyperlink
  for terminals/log viewers that support clickable links (degrades gracefully to plain colored
  text otherwise). Now printed twice — once as soon as it's known (early in the boot log) and
  once in the final "app is running" banner — each time next to a reminder of where to set it
  as your Home Assistant network URL (Settings → System → Network → Home Assistant URL).

## 0.1.0

- Initial release. Real Let's Encrypt certificate for your whole Home Assistant instance, issued
  via the same DNS-01/Route53 automation already used for Islautopia Doorbell hardware — no
  domain, no DNS provider account, no port forwarding. Transparent reverse proxy to Home
  Assistant Core on port 8443. Zero configuration options; self-registers a dedicated identity
  and keeps its certificate renewed automatically in the background.
