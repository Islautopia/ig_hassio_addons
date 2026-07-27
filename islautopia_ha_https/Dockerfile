# 1. BASE IMAGE
FROM alpine:latest

# 2. DEPENDENCIES: curl+jq for the VPS API calls, bash for run.sh, caddy as the TLS proxy.
#    Deliberately NOT go2rtc, NOT openssl self-signed generation - see README.md for why this
#    add-on is a clean break from the legacy islautopia_intercom add-on, not a variant of it.
RUN apk add --no-cache curl jq bash caddy

# 3. ENTRYPOINT
COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
