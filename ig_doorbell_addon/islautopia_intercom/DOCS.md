![Logo](icon.png)
# Islautopia Intercom Engine

**The definitive secure gateway for RTSP-based 2-way audio intercoms.**

---

## 📖 Overview
The **Islautopia Intercom Engine** is a specialized, SSL-hardened gateway designed to bridge the gap between any **RTSP-based video intercom** and Home Assistant. 

Modern web browsers aggressively block microphone access if they detect an "insecure" connection. This Add-on solves this by providing an automated SSL proxy and its own integrated `go2rtc` instance, ensuring a secure context for your video streams so you can enjoy full 2-way audio functionality without browser security blocks.

> **Note:** While this Add-on and its companion *Islautopia Intercom Card* are fully open-source and compatible with any standard RTSP protocol, they have been engineered as the foundational software layer for the **upcoming Islautopia Garage Video Intercom line**—the first hardware designed specifically for seamless Home Assistant integration. Stay tuned for the official launch announcement!

## 🚀 Key Features
* **RTSP to WebRTC Gateway:** Leverages an embedded `go2rtc` instance to handle RTSP streams, optimized for 2-way audio.
* **SSL/TLS Security:** Transparently handles HTTPS/TLS to satisfy browser security requirements for microphone permissions.
* **Plug & Play Integration:** Designed to pair perfectly with the *Islautopia Intercom Card* for HACS.

## 📥 Installation

1. **Add Repository:**
   - In Home Assistant, navigate to **Settings > Add-ons**.
   - Click the **three dots** in the top-right corner and select **Repositories**.
   - Paste your repository URL and click **Add**.
   - Search for **"Islautopia Intercom Engine"** in the Add-on Store and click **Install**.

2. **Configure Network for HTTPS (Essential):**
   - Go to **Settings > System > Local Network**.
   - Enter `https://<YOUR_HASS_IP>:8443` in the Server URL field.
   - Uncheck the **"Automatic"** option to force this manual configuration.
   - Save and restart Home Assistant.

3. **Configure & Start Add-on:**
   - Go to the **Configuration** tab of the Add-on.
   - Set your `intercom_ip`, `webrtc_port`, and `go2rtc_api_port`.
   - *Tip: If you don't know your intercom's IP, check your router's "Connected Devices" list or use a network scanner app (like Fing) to find the device matching your intercom's MAC address.*
   - Click **Start** and check the **Log** tab to ensure the gateway is listening.

## ⚙️ Configuration Parameters
* `intercom_ip`: The local IP address of your RTSP video doorbell.
* `webrtc_port`: The WebRTC port for the stream (Default: 8565).
* `device_name`: Unique identifier for your stream (e.g., `videoportero`).
* `go2rtc_api_port`: The port for the internal `go2rtc` API (Default: 1985).

## 🧠 Why this Add-on?
Unlike standard RTSP-to-WebRTC setups that rely on insecure connections, this Add-on acts as a **Secure Gateway**:
1. It intercepts incoming requests on port `8443`.
2. It manages the TLS handshake, satisfying the browser's "Secure Context" requirement.
3. It allows the browser to enable the microphone, finally bridging the gap between your RTSP intercom and a professional 2-way audio dashboard experience.

## ❓ Troubleshooting
* **"Connecting" status:** Check the Add-on logs. Ensure the RTSP source (your intercom IP) is correctly reachable from the Home Assistant host.
* **Microphone icon disabled:** Verify that you are accessing Home Assistant via `https://<YOUR_HASS_IP>:8443`. If you are using standard HTTP, the browser will block the microphone by design.

---

**Developed by Islautopia Garage.**
*Questions or partnership inquiries? Contact us at: [garage@islautopia.com](mailto:garage@islautopia.com)*