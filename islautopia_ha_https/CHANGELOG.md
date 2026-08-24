# Changelog

## 0.5.0

All of this came out of installing it from the add-on store for the first time.

### Added

- **A button of its own** on the add-on's page, which opens the trust page. Home Assistant renders
  an add-on log as plain text, so **the URLs in it are not links and an add-on cannot make them
  be**. A button can.
- **The trust page over the public hostname too** - which carries a certificate every browser
  already trusts, so that link opens without a single warning.
- **An icon and a logo.** It had neither.

### Fixed

- **The trust page returned 404 on the public hostname.** Its two routes lived only in the
  catch-all site on port 8443; the public-hostname site simply handed everything to Home
  Assistant. Both now come from one shared snippet imported by each, rather than being repeated -
  a defence living in two places falls over as soon as one of them is left behind.

### Why the hostname one matters

The page on port 8099 is **plain HTTP on purpose**: it is the only path that works with no internet
at all. The price is that a modern browser may upgrade it to `https` by itself, or serve it from
cache, and then **it appears not to work** - which is exactly what happened on the first real
install, and it took a private window to get through.

**That is not the add-on**, and it is measured rather than assumed: from outside, port 8099 answers
`200` in plain HTTP, with no redirect and no HSTS header. So rather than fight it, the add-on now
offers a path that cannot have the problem, and says in the log that it is there.

## 0.4.0

**Fixed: reinstalling the app used to throw away the two things it must never regenerate.** The
cloud identity and the private certificate authority lived in the app's own private volume, which
Home Assistant destroys on uninstall — and which is also separate for a local copy and one
installed from a repository. So moving an existing install to the add-on store came back looking
perfectly healthy **at a different address, with an authority no device trusted**. Nothing failed
and nothing said anything; the public hostname simply stopped being the one in your bookmarks and
in Home Assistant's own network setting.

Both now live in the `ssl` share, which survives all of that and is where Home Assistant already
keeps certificates. Anything that can be regenerated — the Let's Encrypt certificate, the cached
addresses — stays in the private volume, where losing it costs nothing.

**New: the durable store doubles as a drop-in.** Put a `ha_instance.json` (and a `ca/`, if you have
one) into `ssl/islautopia_ha_https/` before the first start and the app adopts them instead of
minting new ones. That is what makes moving an existing installation to the add-on repository free:
same hostname, same authority, nothing to reinstall on any device.

An identity or authority left in the old private volume is adopted automatically on first start.
The copy only ever goes **into** the durable store and only when it is empty, so running it twice
cannot overwrite a good copy with a stale one.

**Worth knowing before you upgrade:** the authority's private key now sits in the `ssl` share
rather than in the app's private volume. That share is the conventional place for exactly this kind
of file — Home Assistant's own certificate and key live there — and anyone who can reach it can
already edit your configuration, so it does not widen who can get at it. It is said out loud rather
than left to be discovered.

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
