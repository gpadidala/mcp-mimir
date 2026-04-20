# MCP Prometheus Server — Developer Guide

This guide walks you through building, running, and connecting to the MCP Prometheus server from VS Code.

## Prerequisites

- Docker and Docker Compose installed
- A running Prometheus or Mimir instance
- VS Code with Copilot Chat or Claude Code extension

## Step 1: Configure Environment Variables

Copy the example env file (if you haven't already) and edit it:

```bash
cp .env.example .env
```

Edit `.env` and set your Prometheus URL:

```bash
# If Prometheus runs on the SAME machine as Docker:
PROMETHEUS_URL=http://host.docker.internal:9090

# If Prometheus runs on a DIFFERENT machine:
PROMETHEUS_URL=http://<prometheus-ip>:9090
```

### Optional Configuration

| Variable | Description | Default |
|---|---|---|
| `PROMETHEUS_URL` | Prometheus/Mimir endpoint | `http://host.docker.internal:9090` |
| `PROMETHEUS_ORGID` | Org/tenant ID for multi-tenancy (Mimir, Cortex, Thanos) | _(empty)_ |
| `PROMETHEUS_USERNAME` | Basic auth username | _(empty)_ |
| `PROMETHEUS_PASSWORD` | Basic auth password | _(empty)_ |
| `PROMETHEUS_TOKEN` | Bearer token auth | _(empty)_ |
| `TRANSPORT` | Transport protocol | `sse` |
| `MCP_PORT` | Host port for MCP SSE endpoint | `8080` |
| `METRICS_PORT` | Host port for health/metrics | `9091` |

## Step 2: Build the Docker Image

```bash
cd /path/to/mcp-mimir
docker compose build
```

To force a clean rebuild (e.g., after a version bump):

```bash
docker compose build --no-cache
```

## Step 3: Start the MCP Server

```bash
docker compose up -d
```

## Step 4: Verify the Server Is Running

Run these commands in order to confirm everything is healthy:

```bash
# 1. Check container status (should show "Up" and "healthy")
docker compose ps

# 2. Check logs for startup errors
docker compose logs mcp-prometheus

# 3. Test the health endpoint (should return 200 OK)
curl http://localhost:9091/healthz

# 4. Test the SSE endpoint (should hang/stream — press Ctrl+C to stop)
curl http://localhost:8080/sse

# 5. Verify Prometheus is reachable from inside the container
docker exec mcp-prometheus sh -c 'wget -qO- $PROMETHEUS_URL/api/v1/status/buildinfo'
```

## Step 5: Connect from VS Code

The `.vscode/mcp.json` file is already configured for SSE transport. When VS Code prompts:

1. **MCP Prometheus SSE endpoint URL:**
   - Same machine as Docker: `http://localhost:8080/sse`
   - Different machine: `http://<docker-host-ip>:8080/sse`

2. **Prometheus/Mimir Org ID:**
   - Leave empty unless you are using multi-tenancy

## Step 6: Query Data

Once connected, you can ask natural language questions in the chat:

- "Show me CPU usage for the last hour"
- "What metrics are available?"
- "Query `up` to see which targets are healthy"
- "Show me memory usage across all nodes"
- "What is the current request rate for my services?"

## Troubleshooting

### Container starts but MCP server fails

Check logs for the exact error:

```bash
docker compose logs -f mcp-prometheus
```

### `PROMETHEUS_URL` is unreachable from the container

- If Prometheus is on the host machine, use `http://host.docker.internal:9090` (not `localhost`)
- If Prometheus is on another machine, ensure the firewall allows traffic on port 9090
- Test from inside the container:

```bash
docker exec mcp-prometheus wget -qO- http://host.docker.internal:9090/api/v1/status/buildinfo
```

### Port 8080 is already in use

Change `MCP_PORT` in `.env` to a free port (e.g., `8081`) and restart:

```bash
MCP_PORT=8081 docker compose up -d
```

Then use `http://localhost:8081/sse` in VS Code.

### SSE endpoint returns connection refused

- Confirm the container is running: `docker compose ps`
- Confirm port mapping: `docker port mcp-prometheus`
- Check if another process is using the port: `lsof -i :8080`

### Binary download fails during build

The Dockerfile downloads `mcp-prometheus` from GitHub releases. If this fails:

- Check your internet connection
- Rebuild with no cache: `docker compose build --no-cache`
- Verify the release version exists at https://github.com/giantswarm/mcp-prometheus/releases

### Restarting the server

```bash
# Restart
docker compose restart

# Full stop and start
docker compose down && docker compose up -d
```

## Multi-Org Setup

To run separate MCP server instances per org/tenant, uncomment the additional services in `docker-compose.yml` and configure each with a unique `PROMETHEUS_ORGID` and port mapping. See the comments in `docker-compose.yml` for examples.
