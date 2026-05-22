![Logo](icon.png)
# Islautopia Intercom Engine

**The definitive secure, local gateway for RTSP-based 2-way audio intercoms.**

---

## 📖 Overview
The **Islautopia Intercom Engine** is a specialized, SSL-hardened gateway designed to bridge the gap between any **RTSP-based video intercom** and Home Assistant. 

Modern web browsers aggressively block microphone access if they detect an "insecure" connection. This Add-on solves this by providing an automated local SSL proxy and its own integrated `go2rtc` instance. It ensures a secure context for your video streams so you can enjoy full 2-way audio functionality—all 100% locally, with zero cloud dependencies or complex network routing.

> **Note:** While this Add-on and its companion **[Islautopia Intercom Card](https://github.com/Islautopia/islautopia-intercom-card)** are fully open-source and compatible with any standard RTSP protocol, they have been engineered as the foundational software layer for the **upcoming Islautopia Garage Video Intercom line**—the first hardware designed specifically for seamless Home Assistant integration. Stay tuned for the official launch announcement!

## 🎯 Is this Add-on for you?
To save you time, here is exactly who this is built for, and who might not need it:

* **✅ Who it IS for:** If you access Home Assistant locally (e.g., `http://192.168...`) and your browser blocks the microphone when trying to talk to your intercom. This Add-on provides an extraordinarily simple, "out-of-the-box" secure end-to-end local environment. **No router port forwarding, no DuckDNS, and no complex network tinkering required.**
* **❌ Who it is NOT strictly for:** If you already access your Home Assistant dashboard via a secure remote connection with a valid SSL certificate (such as **Nabu Casa / Home Assistant Cloud**, or your own reverse proxy like NGINX/Cloudflare), your browser already allows microphone access. You technically do not *need* this Add-on to make 2-way audio work.
* **🛡️ Why you might want it anyway:** Even if you use Nabu Casa, you can still install this Add-on to create a **100% local, internet-independent fallback**. If your internet connection drops, this engine ensures your 2-way audio keeps working smoothly on your local network without relying on third-party clouds or external servers.

## 🚀 Key Features
* **Autonomous Local SSL Gateway:** Automatically generates and manages a local certificate (via Caddy) to satisfy browser security requirements, enabling your microphone locally.
* **Built-in Support Portal:** Features a dedicated `/cert` endpoint providing a 1-click download portal to easily install the trusted certificate on your mobile devices and tablets.
* **Collision-Free Architecture:** Configured by default to run on isolated ports (API on 1985, WebRTC on 8565) to prevent conflicts with other existing Add-ons like Frigate.
* **Embedded WebRTC Engine:** Includes a standalone, optimized `go2rtc` instance to handle RTSP-to-WebRTC conversion with zero-latency streaming.
* **Plug & Play Integration:** Designed to pair perfectly with the **[Islautopia Intercom Card](https://github.com/Islautopia/islautopia-intercom-card)** for HACS.


## 📥 Installation & Setup

1. **Add Repository & Install:**
   - In Home Assistant, navigate to **Settings > Add-ons**.
   - Click the **three dots** in the top-right corner and select **Repositories**.
   - Paste the URL address of this repository (`https://github.com/Islautopia/ig_hassio_addons`) and click **Add**.
   - Search for **"Islautopia Intercom Engine"** in the Add-on Store and click **Install**.

2. **Configure & Start Add-on:**
   - Go to the **Configuration** tab of the Add-on.
   - Enter a unique identifier for your stream in the `device_name` field (e.g., `doorbell`).
   - Set your `intercom_ip`, `webrtc_port`, and `go2rtc_api_port`.
   - *Tip: If you don't know your intercom's IP, check your router's "Connected Devices" list or use a network scanner app (like Fing).*
   - Click **Start** and check the **Log** tab. The gateway will print a green success dashboard showing your secure access URL (e.g., `https://<YOUR_HASS_IP>:8443`).
   - *Crucial: This is the exact address you must enter in your browser or configure as the **"Internal URL" (Local Access) in your Home Assistant Companion App** to ensure 2-way audio permissions.*

3. **Configure Network for HTTPS (Essential):**
   - Go to **Settings > System > Local Network** in Home Assistant.
   - Enter `https://<YOUR_HASS_IP>:8443` in the Server URL field.
   - Uncheck the **"Automatic"** option to force this manual configuration.
   - Save and restart Home Assistant.

4. **Trust the Local Certificate (Final Step for 2-Way Audio):**
   - Open a browser on the device you want to use for 2-way audio (phone, tablet, PC).
   - Navigate to the new secure URL support portal: `https://<YOUR_HASS_IP>:8443/cert`.
   - Click the download button to get `islautopia.crt` and install it into your device's trusted root certificates.

## ⚙️ Configuration Parameters
* `intercom_ip`: The local IP address of your RTSP video doorbell.
* `webrtc_port`: The WebRTC port for the stream (Default: 8565).
* `device_name`: Unique identifier for your stream (e.g., `videoportero`).
* `go2rtc_api_port`: The port for the internal `go2rtc` API (Default: 1985).

## ❓ Troubleshooting
* **"Connecting" status:** Check the Add-on logs. Ensure the RTSP source (your intercom IP) is correctly reachable from the Home Assistant host.
* **Microphone icon disabled:** Verify that you are accessing Home Assistant via `https://<YOUR_HASS_IP>:8443` and that you have downloaded and trusted the certificate from the `/cert` portal. If you use standard HTTP, the browser will block the microphone by design.

---

**Developed by Islautopia Garage.**
*Questions or partnership inquiries? Contact us at: [garage@islautopia.com](mailto:garage@islautopia.com)*
