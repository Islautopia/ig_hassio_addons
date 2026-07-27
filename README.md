# Islautopia Garage Home Assistant Add-ons

Welcome to the official **Islautopia Garage** add-on repository for Home Assistant.

This repository hosts professional-grade, privacy-first, and high-performance local gateways. Our software is engineered to maximize local reliability and security without relying on third-party cloud subscriptions.

## 📦 Available Add-ons

### [Islautopia HTTPS for Home Assistant](./islautopia_ha_https)
Real, zero-configuration HTTPS certificate for your whole Home Assistant instance — no domain, no
DNS account, no port forwarding. Solves the "browser blocks the microphone because HA itself
isn't served over HTTPS" problem, which the certificate on the doorbell itself cannot fix (that
cert only secures the connection *to the doorbell*, not the origin serving your HA dashboard).
**Not a Nabu Casa alternative** — it gives no remote access at all, only real local HTTPS. See
the add-on's own README for the full "Security and privacy" explanation before installing.

### [Islautopia Intercom Engine](./islautopia_intercom)
⚠️ **If you own an Islautopia Doorbell (IG Doorbell hardware), install
[`islautopia-doorbell-integration`](https://github.com/Islautopia/islautopia-doorbell-integration)
instead** (HACS integration, zero YAML, native WebRTC/HTTPS/TURN, auto-dispatches "open door"
MQTT messages). This add-on remains fully supported, unchanged, as a **generic RTSP/`go2rtc`
gateway for third-party video intercoms** — see the add-on's own README for the full picture.

The definitive WebRTC and autonomous local HTTPS/SSL gateway for RTSP-based video doorbells. 
It resolves modern browser security blocks regarding microphone access by providing an automated local SSL proxy and an integrated, standalone `go2rtc` instance. 

> 🚀 **Perfect Companion:** This engine is designed to work flawlessly with the **[Islautopia Intercom Card](https://github.com/Islautopia/islautopia-intercom-card)**. We highly recommend installing the custom card via HACS for the ultimate, zero-latency 2-way audio dashboard experience.

*(More advanced tools for the Islautopia Garage ecosystem will be added over time).*

## ⚙️ Installation Guide

To install any of our add-ons, you need to add this custom repository to your Home Assistant instance:

1. In Home Assistant, navigate to **Settings > Add-ons**.
2. Click the **Add-on Store** button in the bottom-right corner.
3. Click the **three vertical dots** in the top-right corner and select **Repositories**.
4. Copy and paste the following URL, then click **Add**:
   `https://github.com/Islautopia/ig_hassio_addons`
5. Close the popup window.
6. Click the three vertical dots again and select **Check for updates** (or Reload).

Scroll down to the bottom of the Add-on Store page, and you will find the new **"Islautopia Add-ons"** section with our gateway ready to be installed with a single click.

## 📞 Support & Partnership
Developed and maintained for the Islautopia Garage ecosystem.
For technical questions, integrations, or general inquiries, please contact us at: [garage@islautopia.com](mailto:garage@islautopia.com)