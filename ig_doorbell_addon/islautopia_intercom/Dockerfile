# 1. IMAGEN BASE PURA DE DOCKER HUB
FROM alpine:latest

# 2. INSTALACIÓN DE DEPENDENCIAS Y CADDY OFICIAL
RUN apk add --no-cache curl jq bash caddy

# 3. DESCARGA EXCLUSIVA DE GO2RTC
RUN ARCH=$(uname -m) \
    && echo "Detectada arquitectura de hardware: ${ARCH}" \
    && if [ "${ARCH}" = "aarch64" ]; then GO_ARCH="arm64"; \
       elif [ "${ARCH}" = "x86_64" ]; then GO_ARCH="amd64"; \
       elif [ "${ARCH}" = "armv7l" ]; then GO_ARCH="armv7"; \
       else GO_ARCH="amd64"; fi \
    && echo "Descargando go2rtc para ${GO_ARCH}..." \
    && curl -L "https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_${GO_ARCH}" -o /usr/local/bin/go2rtc \
    && chmod +x /usr/local/bin/go2rtc

# 4. COPIAR CONFIGURACIONES Y SCRIPT DE ARRANQUE
COPY run.sh /run.sh
RUN chmod a+x /run.sh

COPY go2rtc.yaml /etc/

# 5. EJECUCIÓN DIRECTA COMO PID 1
CMD [ "/run.sh" ]