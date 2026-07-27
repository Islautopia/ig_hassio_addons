# Changelog

## 0.2.0

- Highlight the local access URL in the startup log: bold color, wrapped as an OSC 8 hyperlink
  for terminals/log viewers that support clickable links (degrades gracefully to plain colored
  text otherwise). Now printed twice — once as soon as it's known (early in the boot log) and
  once in the final "add-on is running" banner — each time next to a reminder of where to set it
  as your Home Assistant network URL (Settings → System → Network → Home Assistant URL).

## 0.1.0

- Initial release. Real Let's Encrypt certificate for your whole Home Assistant instance, issued
  via the same DNS-01/Route53 automation already used for Islautopia Doorbell hardware — no
  domain, no DNS provider account, no port forwarding. Transparent reverse proxy to Home
  Assistant Core on port 8443. Zero configuration options; self-registers a dedicated identity
  and keeps its certificate renewed automatically in the background.
