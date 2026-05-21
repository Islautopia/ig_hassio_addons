# 1. BASE IMAGE FROM DOCKER HUB
FROM alpine:latest

# 2. INSTALL DEPENDENCIES AND OFFICIAL CADDY
RUN apk add --no-cache curl jq bash caddy

# 3. DOWNLOAD GO2RTC BINARY
RUN ARCH=$(uname -m) \
    && echo "Detected hardware architecture: ${ARCH}" \
    && if [ "${ARCH}" = "aarch64" ]; then GO_ARCH="arm64"; \
       elif [ "${ARCH}" = "x86_64" ]; then GO_ARCH="amd64"; \
       elif [ "${ARCH}" = "armv7l" ]; then GO_ARCH="armv7"; \
       else GO_ARCH="amd64"; fi \
    && echo "Downloading go2rtc for ${GO_ARCH}..." \
    && curl -L "https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_${GO_ARCH}" -o /usr/local/bin/go2rtc \
    && chmod +x /usr/local/bin/go2rtc

# 4. COPY CONFIGURATIONS AND ENTRYPOINT SCRIPT
COPY run.sh /run.sh
RUN chmod a+x /run.sh

COPY go2rtc.yaml /etc/

# 5. EXECUTE SCRIPT AS PID 1
CMD [ "/run.sh" ]