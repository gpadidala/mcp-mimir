FROM alpine:3.20

ARG TARGETARCH=amd64
ARG VERSION=0.0.59

RUN apk add --no-cache ca-certificates wget

# Download the mcp-prometheus binary from GitHub releases
RUN wget -O /usr/local/bin/mcp-prometheus \
    "https://github.com/giantswarm/mcp-prometheus/releases/download/v${VERSION}/mcp-prometheus_linux_${TARGETARCH}" && \
    chmod +x /usr/local/bin/mcp-prometheus

# All configurable at runtime via -e or docker-compose environment
ENV PROMETHEUS_URL=""
ENV PROMETHEUS_ORGID=""
ENV PROMETHEUS_USERNAME=""
ENV PROMETHEUS_PASSWORD=""
ENV PROMETHEUS_TOKEN=""
ENV TRANSPORT="sse"
ENV HTTP_ADDR=":8080"
ENV METRICS_ADDR=":9091"

EXPOSE 8080
EXPOSE 9091

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:9091/healthz || exit 1

# Shell entrypoint reads env vars at runtime — nothing is hardcoded
ENTRYPOINT ["/bin/sh", "-c", "exec mcp-prometheus serve \
    --transport \"${TRANSPORT}\" \
    --http-addr \"${HTTP_ADDR}\" \
    --metrics-addr \"${METRICS_ADDR}\""]
