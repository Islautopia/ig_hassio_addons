# 1. BASE IMAGE
FROM alpine:latest

# 2. DEPENDENCIES
#    curl + jq  -> the cloud API calls (identity, IP report, certificate)
#    bash       -> run.sh
#    caddy      -> the TLS proxy in front of Home Assistant
#    openssl    -> the private CA and the local certificate it issues, which are
#                  what keeps HTTPS (and therefore microphone access) working
#                  when there is no internet to resolve the public hostname.
RUN apk add --no-cache curl jq bash caddy openssl

# 3. ENTRYPOINT
COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
