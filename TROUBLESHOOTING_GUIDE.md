# MCP Prometheus Server — Troubleshooting Guide

A comprehensive troubleshooting reference covering basic to advanced issues for Docker and Kubernetes (AKS) deployments.

## Table of Contents

1. [Quick Diagnostics Checklist](#quick-diagnostics-checklist)
2. [Basic: Docker Issues](#basic-docker-issues)
   - [Container won't start](#container-wont-start)
   - [Container starts but MCP server crashes](#container-starts-but-mcp-server-crashes)
   - [Health endpoint not responding](#health-endpoint-not-responding)
   - [SSE endpoint returns connection refused](#sse-endpoint-returns-connection-refused)
   - [Port already in use](#port-already-in-use)
3. [Basic: Connectivity Issues](#basic-connectivity-issues)
   - [Cannot reach Prometheus from container](#cannot-reach-prometheus-from-container)
   - [wget: bad port '' error](#wget-bad-port--error)
   - [Connection refused to Prometheus](#connection-refused-to-prometheus)
   - [Timeout connecting to Prometheus](#timeout-connecting-to-prometheus)
4. [Basic: VS Code Integration Issues](#basic-vs-code-integration-issues)
   - [MCP server not showing in VS Code](#mcp-server-not-showing-in-vs-code)
   - [405 Method Not Allowed on connect](#405-method-not-allowed-on-connect)
   - [SSE stream drops / disconnects](#sse-stream-drops--disconnects)
   - [Tools not appearing in chat](#tools-not-appearing-in-chat)
5. [Intermediate: Configuration Issues](#intermediate-configuration-issues)
   - [Environment variables not loading](#environment-variables-not-loading)
   - [Multi-tenancy / Org ID not working](#multi-tenancy--org-id-not-working)
   - [Authentication failures](#authentication-failures)
   - [Wrong Prometheus data returned](#wrong-prometheus-data-returned)
6. [Intermediate: Build Issues](#intermediate-build-issues)
   - [Docker build fails — binary download error](#docker-build-fails--binary-download-error)
   - [Architecture mismatch (ARM vs AMD64)](#architecture-mismatch-arm-vs-amd64)
   - [Image size too large](#image-size-too-large)
7. [Advanced: Kubernetes / AKS Issues](#advanced-kubernetes--aks-issues)
   - [Pod in CrashLoopBackOff](#pod-in-crashloopbackoff)
   - [Pod stuck in Pending](#pod-stuck-in-pending)
   - [Readiness probe failing](#readiness-probe-failing)
   - [HPA not scaling](#hpa-not-scaling)
   - [Ingress not routing traffic](#ingress-not-routing-traffic)
   - [NetworkPolicy blocking traffic](#networkpolicy-blocking-traffic)
   - [TLS / certificate issues (prod)](#tls--certificate-issues-prod)
8. [Advanced: Performance Issues](#advanced-performance-issues)
   - [Slow query responses](#slow-query-responses)
   - [High memory usage](#high-memory-usage)
   - [SSE connections piling up](#sse-connections-piling-up)
9. [Advanced: Debugging Techniques](#advanced-debugging-techniques)
   - [Container shell access](#container-shell-access)
   - [Network debugging from inside the container](#network-debugging-from-inside-the-container)
   - [Capturing MCP traffic](#capturing-mcp-traffic)
   - [Reading Prometheus metrics from the MCP server](#reading-prometheus-metrics-from-the-mcp-server)
10. [Error Reference Table](#error-reference-table)

---

## Quick Diagnostics Checklist

Run these commands first to identify the problem area:

```bash
# 1. Is the container running?
docker compose ps

# 2. Are there errors in the logs?
docker compose logs --tail=50 mcp-prometheus

# 3. Is the health endpoint responding?
curl -s -o /dev/null -w "%{http_code}" http://localhost:9091/healthz

# 4. Is the SSE endpoint responding?
curl -s --max-time 3 http://localhost:8080/sse

# 5. Can the container reach Prometheus?
docker exec mcp-prometheus sh -c 'wget -qO- $PROMETHEUS_URL/api/v1/status/buildinfo'

# 6. Are the environment variables set correctly?
docker exec mcp-prometheus env | grep PROMETHEUS
```

---

## Basic: Docker Issues

### Container won't start

**Symptoms:** `docker compose ps` shows the container as exited or restarting.

**Diagnosis:**
```bash
docker compose logs mcp-prometheus
```

**Common causes and fixes:**

| Cause | Fix |
|-------|-----|
| Binary not found | Rebuild: `docker compose build --no-cache` |
| Permission denied on binary | Check Dockerfile has `chmod +x` on the binary |
| Invalid env var format | Check `.env` for syntax errors (no spaces around `=`) |

### Container starts but MCP server crashes

**Symptoms:** Container shows as "Restarting" and health check fails.

**Diagnosis:**
```bash
# Watch logs in real-time
docker compose logs -f mcp-prometheus

# Check exit code
docker inspect mcp-prometheus --format='{{.State.ExitCode}}'
```

**Common causes:**

- **Exit code 1:** The `mcp-prometheus serve` command failed. Check logs for the specific error.
- **Exit code 137:** Out of memory (OOM killed). Increase Docker memory limits.
- **Exit code 139:** Segfault — likely architecture mismatch (see [Architecture mismatch](#architecture-mismatch-arm-vs-amd64)).

### Health endpoint not responding

**Symptoms:** `curl http://localhost:9091/healthz` returns connection refused or times out.

**Steps:**
```bash
# Check container is running
docker compose ps

# Check port mapping
docker port mcp-prometheus

# Check if metrics port is exposed
docker inspect mcp-prometheus --format='{{range .NetworkSettings.Ports}}{{.}}{{end}}'
```

**Fix:** Ensure `METRICS_ADDR` is set to `:9091` (with the colon) in `.env` and the port is mapped in `docker-compose.yml`.

### SSE endpoint returns connection refused

**Symptoms:** `curl http://localhost:8080/sse` fails.

**Steps:**
```bash
# Confirm the container is running
docker compose ps

# Confirm port mapping
docker port mcp-prometheus

# Check if another process is using port 8080
lsof -i :8080
```

**Fix:** If another process is on port 8080, change `MCP_PORT` in `.env`:
```bash
MCP_PORT=8081
docker compose down && docker compose up -d
```

### Port already in use

**Symptoms:** `docker compose up` fails with "port is already allocated".

**Diagnosis:**
```bash
# Find what's using the port
lsof -i :8080
# or
netstat -tlnp | grep 8080
```

**Fix:** Either stop the conflicting process or change `MCP_PORT` in `.env`.

---

## Basic: Connectivity Issues

### Cannot reach Prometheus from container

**Symptoms:** MCP server starts but queries return errors about connection refused or timeouts.

**Key concept:** Inside a Docker container, `localhost` refers to the container itself, not your host machine.

**Fix by scenario:**

| Prometheus location | Use this URL |
|---|---|
| Running on the host machine | `http://host.docker.internal:9090` |
| Running in another Docker container (same compose) | `http://<service-name>:9090` |
| Running in another Docker container (different compose) | Create a shared network or use host IP |
| Running on a remote server | `http://<server-ip>:9090` |

**Verify from inside the container:**
```bash
docker exec mcp-prometheus sh -c 'wget -qO- $PROMETHEUS_URL/api/v1/status/buildinfo'
```

### wget: bad port '' error

**Symptoms:** Running `docker exec mcp-prometheus wget -qO- $PROMETHEUS_URL/...` returns "wget: bad port ''".

**Cause:** The `$PROMETHEUS_URL` variable is being expanded by your host shell (where it's empty), not inside the container.

**Fix:** Wrap the command in `sh -c` with single quotes:
```bash
docker exec mcp-prometheus sh -c 'wget -qO- $PROMETHEUS_URL/api/v1/status/buildinfo'
```

### Connection refused to Prometheus

**Symptoms:** `wget: can't connect to remote host: Connection refused`

**Causes:**
1. Prometheus is not running at the configured URL
2. Firewall is blocking the connection
3. Wrong port number

**Diagnosis:**
```bash
# Test from the HOST machine first
curl http://localhost:9090/api/v1/status/buildinfo

# If that works, test from inside the container
docker exec mcp-prometheus sh -c 'wget -qO- http://host.docker.internal:9090/api/v1/status/buildinfo'

# Check if Prometheus is running
docker ps | grep prometheus
# or
lsof -i :9090
```

### Timeout connecting to Prometheus

**Symptoms:** Queries hang and eventually time out.

**Causes:**
1. Firewall blocking traffic between Docker network and host/remote
2. Prometheus is overloaded
3. DNS resolution failing inside the container

**Diagnosis:**
```bash
# Test DNS resolution
docker exec mcp-prometheus sh -c 'nslookup host.docker.internal'

# Test raw connectivity
docker exec mcp-prometheus sh -c 'wget --spider --timeout=5 $PROMETHEUS_URL'
```

---

## Basic: VS Code Integration Issues

### MCP server not showing in VS Code

**Steps:**
1. Verify `.vscode/mcp.json` exists in your workspace root
2. Reload VS Code window: `Ctrl+Shift+P` > "Developer: Reload Window"
3. Check the MCP server is running: `curl http://localhost:8080/sse`
4. Check the VS Code Output panel > select "MCP" from the dropdown for error details

### 405 Method Not Allowed on connect

**Symptoms:** VS Code logs show a 405 error when connecting.

**This is normal.** VS Code tries `streamable-http` transport first, gets a 405, then falls back to SSE. The connection should succeed after the fallback.

If it doesn't connect after the 405:
- Check the URL in the VS Code prompt matches your MCP server (default: `http://localhost:8080/sse`)
- Ensure `TRANSPORT=sse` is set in `.env`

### SSE stream drops / disconnects

**Causes:**
- Container restarted (check `docker compose logs`)
- Network interruption
- Proxy or firewall terminating long-lived connections

**Fix:**
- VS Code should auto-reconnect. If not, reload the window.
- If using a reverse proxy, disable response buffering:
  ```
  proxy_buffering off;
  proxy_read_timeout 86400s;
  ```

### Tools not appearing in chat

**Steps:**
1. Confirm the SSE connection is active (check MCP panel in VS Code)
2. Restart the MCP server: `docker compose restart`
3. Reload VS Code window
4. Check that `TRANSPORT=sse` is set (not `stdio`)

---

## Intermediate: Configuration Issues

### Environment variables not loading

**Symptoms:** Container starts but uses default values instead of your `.env` settings.

**Diagnosis:**
```bash
# Check what the container actually sees
docker exec mcp-prometheus env | grep -E 'PROMETHEUS|TRANSPORT|HTTP_ADDR|METRICS_ADDR'
```

**Common causes:**
- `.env` file is not in the same directory as `docker-compose.yml`
- Syntax error in `.env` (spaces around `=`, quotes not needed)
- Variable overridden by shell environment (`export` takes precedence over `.env`)

**Correct `.env` format:**
```bash
# Good
PROMETHEUS_URL=http://host.docker.internal:9090

# Bad — spaces around =
PROMETHEUS_URL = http://host.docker.internal:9090

# Bad — unnecessary quotes
PROMETHEUS_URL="http://host.docker.internal:9090"
```

### Multi-tenancy / Org ID not working

**Symptoms:** Queries return data from the wrong tenant or "no data" errors.

**Diagnosis:**
```bash
# Check the org ID is set
docker exec mcp-prometheus env | grep ORGID
```

**Fix:** Set `PROMETHEUS_ORGID` in `.env` or pass it per-query:
```json
{ "name": "execute_query", "arguments": { "query": "up", "org_id": "my-tenant" } }
```

**Verify Mimir accepts the org ID:**
```bash
curl -H "X-Scope-OrgID: my-tenant" http://<mimir-url>/api/v1/query?query=up
```

### Authentication failures

**Symptoms:** Queries return 401 Unauthorized or 403 Forbidden.

**For basic auth:**
```bash
# Set in .env
PROMETHEUS_USERNAME=myuser
PROMETHEUS_PASSWORD=mypassword

# Verify manually
curl -u myuser:mypassword http://<prometheus-url>/api/v1/status/buildinfo
```

**For bearer token:**
```bash
# Set in .env
PROMETHEUS_TOKEN=my-bearer-token

# Verify manually
curl -H "Authorization: Bearer my-bearer-token" http://<prometheus-url>/api/v1/status/buildinfo
```

### Wrong Prometheus data returned

**Symptoms:** Queries succeed but return unexpected or empty results.

**Diagnosis:**
```bash
# Check which Prometheus the MCP server is talking to
docker exec mcp-prometheus sh -c 'echo $PROMETHEUS_URL'

# Run a basic query directly against Prometheus
curl 'http://<prometheus-url>/api/v1/query?query=up'

# Compare with MCP server result
# (use the execute_query tool in VS Code)
```

**Common causes:**
- Pointing to the wrong Prometheus instance
- Wrong org ID for multi-tenant setups
- Time range mismatch (Prometheus data has expired based on retention)

---

## Intermediate: Build Issues

### Docker build fails — binary download error

**Symptoms:** Build fails at the `wget` step downloading the mcp-prometheus binary.

**Causes and fixes:**

| Cause | Fix |
|-------|-----|
| No internet access | Check Docker's network settings and DNS |
| GitHub rate limited | Wait a few minutes and retry, or use a mirror |
| Version doesn't exist | Check available versions at the [releases page](https://github.com/giantswarm/mcp-prometheus/releases) |
| Corporate proxy | Set `HTTP_PROXY` and `HTTPS_PROXY` build args |

**Build with proxy:**
```bash
docker compose build --build-arg HTTP_PROXY=http://proxy:3128 --build-arg HTTPS_PROXY=http://proxy:3128
```

**Force clean rebuild:**
```bash
docker compose build --no-cache
```

### Architecture mismatch (ARM vs AMD64)

**Symptoms:** Container crashes with `exec format error` or segfault (exit code 139).

**Cause:** The binary architecture doesn't match your system. The Dockerfile defaults to `amd64`.

**Fix for Apple Silicon (M1/M2/M3):**
```bash
docker compose build --build-arg TARGETARCH=arm64
```

**Check your architecture:**
```bash
uname -m
# x86_64 = amd64
# aarch64 or arm64 = arm64
```

### Image size too large

The image is based on `alpine:3.20` and should be small (~30-50MB). If it's large:
```bash
docker images mcp-prometheus
```

**Fix:** Ensure you're not copying unnecessary files. The Dockerfile only downloads the binary — no source code is included.

---

## Advanced: Kubernetes / AKS Issues

### Pod in CrashLoopBackOff

**Diagnosis:**
```bash
# Get pod name
kubectl get pods -n mcp-prometheus-<env> -l app.kubernetes.io/name=mcp-prometheus

# Check logs
kubectl logs -n mcp-prometheus-<env> <pod-name> --previous

# Check events
kubectl describe pod -n mcp-prometheus-<env> <pod-name>
```

**Common causes:**
- ConfigMap or Secret not created — check `envFrom` references exist
- Prometheus URL unreachable from the cluster
- Image pull error — verify ACR credentials and image tag

### Pod stuck in Pending

**Diagnosis:**
```bash
kubectl describe pod -n mcp-prometheus-<env> <pod-name>
```

**Common causes:**

| Cause | Fix |
|-------|-----|
| Insufficient CPU/memory | Reduce resource requests or scale the cluster |
| Node affinity/anti-affinity can't be satisfied | Check topology constraints in the overlay |
| PVC pending (if applicable) | Check storage class and PV availability |

### Readiness probe failing

**Symptoms:** Pod is Running but not Ready. Service doesn't route traffic to it.

**Diagnosis:**
```bash
# Check probe configuration
kubectl describe pod -n mcp-prometheus-<env> <pod-name> | grep -A5 Readiness

# Test the endpoint from inside the pod
kubectl exec -n mcp-prometheus-<env> <pod-name> -- wget -qO- http://localhost:9091/readyz
```

**Fix:** The readiness probe hits `/readyz` on port 9091. Ensure:
- `METRICS_ADDR` is set to `:9091`
- The server has time to start (increase `initialDelaySeconds` if needed)

### HPA not scaling

**Diagnosis:**
```bash
kubectl get hpa -n mcp-prometheus-<env>

# Check if metrics-server is running
kubectl top pods -n mcp-prometheus-<env>
```

**Common causes:**
- Metrics server not installed in the cluster
- Resource requests not set (HPA needs requests to calculate utilization)
- Already at max replicas

### Ingress not routing traffic

**Diagnosis:**
```bash
# Check ingress status
kubectl get ingress -n mcp-prometheus-<env>

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

**SSE-specific fix:** The ingress must disable proxy buffering for SSE:
```yaml
annotations:
  nginx.ingress.kubernetes.io/proxy-buffering: "off"
  nginx.ingress.kubernetes.io/proxy-read-timeout: "86400"
  nginx.ingress.kubernetes.io/proxy-send-timeout: "86400"
```

### NetworkPolicy blocking traffic

**Applies to:** Prod environment only (where NetworkPolicy is deployed).

**Diagnosis:**
```bash
kubectl get networkpolicy -n mcp-prometheus-prod
kubectl describe networkpolicy -n mcp-prometheus-prod
```

**Fix:** Ensure the NetworkPolicy allows:
- **Ingress:** From the ingress controller namespace on port 8080
- **Egress:** To the Prometheus/Mimir endpoint on its port

### TLS / certificate issues (prod)

**Symptoms:** HTTPS connections fail, cert-manager not issuing certificates.

**Diagnosis:**
```bash
# Check certificate status
kubectl get certificate -n mcp-prometheus-prod
kubectl describe certificate -n mcp-prometheus-prod

# Check cert-manager logs
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager
```

---

## Advanced: Performance Issues

### Slow query responses

**Causes and fixes:**

| Cause | Diagnosis | Fix |
|-------|-----------|-----|
| Heavy PromQL query | Check Prometheus query log | Simplify the query, add label filters |
| Prometheus overloaded | Check Prometheus `/metrics` for query queue | Scale Prometheus or add caching |
| Network latency | `time curl <prometheus-url>/api/v1/query?query=up` | Move MCP server closer to Prometheus |
| Too many concurrent queries | Check MCP server metrics | Scale up replicas (K8s) |

### High memory usage

**Diagnosis:**
```bash
# Docker
docker stats mcp-prometheus

# Kubernetes
kubectl top pod -n mcp-prometheus-<env>
```

**Fix:**
- Avoid queries that return massive result sets (e.g., `{__name__=~".+"}`)
- Add label filters to narrow results
- Increase memory limits if legitimate usage

### SSE connections piling up

**Symptoms:** Memory grows over time, many idle connections.

**Diagnosis:**
```bash
# Check active connections (inside container)
docker exec mcp-prometheus sh -c 'netstat -an | grep 8080 | grep ESTABLISHED | wc -l'
```

**Fix:**
- Ensure VS Code clients disconnect properly when closing
- Restart the MCP server periodically if in non-production environments
- In Kubernetes, configure connection timeouts on the ingress

---

## Advanced: Debugging Techniques

### Container shell access

```bash
# Get a shell inside the running container
docker exec -it mcp-prometheus /bin/sh

# For Kubernetes
kubectl exec -it -n mcp-prometheus-<env> <pod-name> -- /bin/sh
```

### Network debugging from inside the container

```bash
# DNS resolution
docker exec mcp-prometheus sh -c 'nslookup host.docker.internal'

# Test TCP connectivity
docker exec mcp-prometheus sh -c 'wget --spider --timeout=5 http://host.docker.internal:9090'

# Check routing
docker exec mcp-prometheus sh -c 'ip route'

# Check what the MCP server sees as env vars
docker exec mcp-prometheus env
```

### Capturing MCP traffic

To see what the MCP server is sending/receiving:

```bash
# Watch SSE events in real-time
curl -N http://localhost:8080/sse

# Watch container logs with timestamps
docker compose logs -f --timestamps mcp-prometheus
```

### Reading Prometheus metrics from the MCP server

The MCP server exposes its own metrics on port 9091:

```bash
# All metrics
curl http://localhost:9091/metrics

# Filter for specific metrics
curl -s http://localhost:9091/metrics | grep mcp
```

---

## Error Reference Table

| Error Message | Cause | Fix |
|---|---|---|
| `wget: bad port ''` | `$PROMETHEUS_URL` expanded on host, not in container | Use `sh -c '...'` with single quotes |
| `Connection refused` | Prometheus not running or wrong URL | Verify Prometheus is running and URL is correct |
| `Connection timed out` | Firewall or network issue | Check firewall rules and Docker networking |
| `401 Unauthorized` | Missing or wrong auth credentials | Set `PROMETHEUS_USERNAME`/`PROMETHEUS_PASSWORD` or `PROMETHEUS_TOKEN` |
| `403 Forbidden` | Auth valid but insufficient permissions | Check Prometheus/Mimir RBAC or tenant permissions |
| `405 Method Not Allowed` | VS Code trying streamable-http first | Normal — VS Code falls back to SSE automatically |
| `502 Bad Gateway` | Ingress can't reach the MCP server pod | Check pod readiness and service selectors |
| `503 Service Unavailable` | No ready pods behind the service | Check pod health and readiness probes |
| `exec format error` | Binary architecture mismatch | Rebuild with correct `TARGETARCH` (arm64 or amd64) |
| `OOMKilled` | Container exceeded memory limit | Increase memory limits or optimize queries |
| `CrashLoopBackOff` | Server crashing repeatedly | Check logs with `kubectl logs --previous` |
| `ImagePullBackOff` | Can't pull the container image | Check ACR credentials and image name |
| `no data` in query results | Wrong org ID, time range, or metric name | Verify org ID, check metric exists with `list_label_values` |
