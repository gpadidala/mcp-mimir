# MCP Prometheus Server — Scaling Guide

A comprehensive guide for scaling the MCP Prometheus server from a single Docker container to a highly available, auto-scaling Kubernetes deployment.

## Table of Contents

1. [Scaling Overview](#scaling-overview)
2. [Basic: Understanding Resource Requirements](#basic-understanding-resource-requirements)
   - [Resource profiling](#resource-profiling)
   - [Baseline metrics](#baseline-metrics)
   - [Capacity estimation](#capacity-estimation)
3. [Basic: Vertical Scaling (Docker)](#basic-vertical-scaling-docker)
   - [Increasing CPU and memory limits](#increasing-cpu-and-memory-limits)
   - [Docker resource configuration](#docker-resource-configuration)
   - [When vertical scaling is enough](#when-vertical-scaling-is-enough)
4. [Basic: Multi-Instance Scaling (Docker)](#basic-multi-instance-scaling-docker)
   - [Running multiple containers](#running-multiple-containers)
   - [Port allocation strategy](#port-allocation-strategy)
   - [Load balancing with NGINX](#load-balancing-with-nginx)
5. [Intermediate: Horizontal Pod Autoscaling (Kubernetes)](#intermediate-horizontal-pod-autoscaling-kubernetes)
   - [How HPA works with MCP](#how-hpa-works-with-mcp)
   - [CPU-based autoscaling](#cpu-based-autoscaling)
   - [Memory-based autoscaling](#memory-based-autoscaling)
   - [Custom metrics autoscaling](#custom-metrics-autoscaling)
   - [HPA tuning and behavior](#hpa-tuning-and-behavior)
6. [Intermediate: Per-Environment Scaling](#intermediate-per-environment-scaling)
   - [Dev environment](#dev-environment)
   - [Perf environment](#perf-environment)
   - [Prod environment](#prod-environment)
   - [Environment comparison](#environment-comparison)
7. [Intermediate: Resource Requests and Limits](#intermediate-resource-requests-and-limits)
   - [Setting the right requests](#setting-the-right-requests)
   - [Setting the right limits](#setting-the-right-limits)
   - [Quality of Service (QoS) classes](#quality-of-service-qos-classes)
   - [Vertical Pod Autoscaler (VPA)](#vertical-pod-autoscaler-vpa)
8. [Advanced: High Availability (HA)](#advanced-high-availability-ha)
   - [Pod anti-affinity](#pod-anti-affinity)
   - [Topology spread constraints](#topology-spread-constraints)
   - [PodDisruptionBudget](#poddisruptionbudget)
   - [Multi-zone deployment](#multi-zone-deployment)
9. [Advanced: SSE Connection Scaling](#advanced-sse-connection-scaling)
   - [Understanding SSE connection lifecycle](#understanding-sse-connection-lifecycle)
   - [Connection limits per pod](#connection-limits-per-pod)
   - [Load balancer sticky sessions](#load-balancer-sticky-sessions)
   - [Connection draining on scale-down](#connection-draining-on-scale-down)
10. [Advanced: Multi-Tenant Scaling](#advanced-multi-tenant-scaling)
    - [Shared server scaling](#shared-server-scaling)
    - [Dedicated server per tenant](#dedicated-server-per-tenant)
    - [Tenant-aware autoscaling](#tenant-aware-autoscaling)
11. [Advanced: Cluster Autoscaling (AKS)](#advanced-cluster-autoscaling-aks)
    - [Node pool autoscaling](#node-pool-autoscaling)
    - [Spot instances for cost optimization](#spot-instances-for-cost-optimization)
    - [Node selectors and taints](#node-selectors-and-taints)
12. [Advanced: Performance Tuning](#advanced-performance-tuning)
    - [Optimizing Prometheus queries](#optimizing-prometheus-queries)
    - [Connection pooling](#connection-pooling)
    - [Ingress tuning for SSE](#ingress-tuning-for-sse)
    - [Kernel tuning for high connections](#kernel-tuning-for-high-connections)
13. [Monitoring Scaling Health](#monitoring-scaling-health)
14. [Scaling Decision Matrix](#scaling-decision-matrix)
15. [Cost Optimization](#cost-optimization)

---

## Scaling Overview

```
                    Scaling Dimensions

     Vertical                          Horizontal
  (bigger pods)                     (more pods)
       |                                 |
  CPU + Memory                    Replicas + HPA
       |                                 |
  +----v--------+              +---------v----------+
  | 1 pod with  |              | N pods behind      |
  | more CPU/RAM|              | Service + Ingress  |
  +-----------+-+              +-+------------------+
              |                  |
              +--------+---------+
                       |
              Infrastructure Scaling
              (more/bigger nodes)
                       |
              +--------v---------+
              | AKS Cluster      |
              | Autoscaler       |
              | + Node Pools     |
              +------------------+
```

**Key scaling characteristics of the MCP server:**
- **Stateless** — any pod can handle any request, no shared state
- **Long-lived SSE connections** — each VS Code client holds one persistent connection
- **CPU-bound during queries** — PromQL parsing and result processing
- **Memory-bound for large results** — queries returning thousands of series

---

## Basic: Understanding Resource Requirements

### Resource profiling

Measure actual resource usage before scaling:

```bash
# Docker — real-time resource usage
docker stats mcp-prometheus

# Docker — detailed container inspection
docker inspect mcp-prometheus --format='{{.HostConfig.Memory}} {{.HostConfig.NanoCpus}}'

# Kubernetes — pod resource usage
kubectl top pod -n mcp-prometheus-<env>

# Kubernetes — historical usage (if Prometheus is scraping the MCP server)
# CPU usage over the last hour
curl 'http://localhost:9090/api/v1/query?query=rate(container_cpu_usage_seconds_total{pod=~"mcp-prometheus.*"}[1h])'
```

### Baseline metrics

Typical resource consumption per pod:

| Workload | CPU (avg) | CPU (peak) | Memory (avg) | Memory (peak) | Connections |
|----------|-----------|------------|--------------|----------------|-------------|
| Idle (no queries) | ~5m | ~10m | ~30Mi | ~40Mi | 0 |
| Light (1-5 queries/min) | ~50m | ~200m | ~50Mi | ~100Mi | 1-5 |
| Moderate (10-30 queries/min) | ~200m | ~500m | ~100Mi | ~256Mi | 5-15 |
| Heavy (50+ queries/min) | ~500m | ~1 core | ~256Mi | ~512Mi | 15-50 |
| Burst (complex PromQL) | ~1 core | ~2 cores | ~512Mi | ~1Gi | N/A |

### Capacity estimation

**Formula:**
```
Required pods = ceil(peak_concurrent_connections / connections_per_pod)
```

**Example:**
- 20 developers using VS Code with MCP
- Each holds 1 SSE connection
- Each pod handles ~50 connections comfortably
- Required: ceil(20 / 50) = 1 pod (but use 2+ for HA)

---

## Basic: Vertical Scaling (Docker)

### Increasing CPU and memory limits

```yaml
# docker-compose.yml
services:
  mcp-prometheus:
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 1G
        reservations:
          cpus: "0.5"
          memory: 256M
```

Or using Docker run:
```bash
docker run -d --name mcp-prometheus \
  --cpus="2.0" \
  --memory="1g" \
  --memory-swap="1g" \
  -p 8080:8080 -p 9091:9091 \
  -e PROMETHEUS_URL=http://host.docker.internal:9090 \
  mcp-prometheus:latest
```

### Docker resource configuration

| Setting | Description | Recommended |
|---------|-------------|-------------|
| `--cpus` | Max CPU cores | Start with 1.0, increase if CPU-throttled |
| `--memory` | Max memory | Start with 256m, increase if OOMKilled |
| `--memory-swap` | Max swap | Set equal to `--memory` (disable swap) |
| `--pids-limit` | Max processes | 200 (prevents fork bombs) |

### When vertical scaling is enough

Vertical scaling is sufficient when:
- Single user or small team (< 10 users)
- Queries are not frequent (< 30/min)
- No HA requirement
- Running on Docker Desktop

**Move to horizontal scaling when:**
- Multiple users experience slow responses
- CPU consistently above 80%
- You need high availability

---

## Basic: Multi-Instance Scaling (Docker)

### Running multiple containers

```yaml
# docker-compose.yml
services:
  mcp-prometheus-1:
    image: mcp-prometheus:latest
    container_name: mcp-prometheus-1
    ports:
      - "8081:8080"
      - "9092:9091"
    environment:
      - PROMETHEUS_URL=${PROMETHEUS_URL:-http://host.docker.internal:9090}
      - TRANSPORT=sse

  mcp-prometheus-2:
    image: mcp-prometheus:latest
    container_name: mcp-prometheus-2
    ports:
      - "8082:8080"
      - "9093:9091"
    environment:
      - PROMETHEUS_URL=${PROMETHEUS_URL:-http://host.docker.internal:9090}
      - TRANSPORT=sse
```

### Port allocation strategy

| Instance | MCP Port | Metrics Port | Use Case |
|----------|----------|--------------|----------|
| mcp-prometheus-1 | 8081 | 9092 | Team Alpha |
| mcp-prometheus-2 | 8082 | 9093 | Team Beta |
| mcp-prometheus-3 | 8083 | 9094 | Team Gamma |

### Load balancing with NGINX

Put NGINX in front of multiple MCP instances:

```nginx
# nginx.conf
upstream mcp_backends {
    # ip_hash ensures same client always connects to same backend
    # (important for SSE connections)
    ip_hash;
    server localhost:8081;
    server localhost:8082;
}

server {
    listen 8080;

    # SSE-specific settings
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 86400s;
    proxy_send_timeout 86400s;

    location / {
        proxy_pass http://mcp_backends;
        proxy_set_header Host $host;
        proxy_set_header Connection '';
        proxy_http_version 1.1;
        chunked_transfer_encoding off;
    }
}
```

```yaml
# docker-compose.yml — add NGINX
services:
  nginx:
    image: nginx:alpine
    ports:
      - "8080:8080"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - mcp-prometheus-1
      - mcp-prometheus-2
```

---

## Intermediate: Horizontal Pod Autoscaling (Kubernetes)

### How HPA works with MCP

```
                  HPA Controller
                       |
          monitors CPU/Memory usage
                       |
        +------+-------+-------+------+
        |      |               |      |
     Pod 1   Pod 2          Pod 3   Pod 4
     (SSE)   (SSE)          (SSE)   (SSE)
        \      |               |      /
         \     |               |     /
          Service (load balances new connections)
```

**Important:** When HPA scales down, pods with active SSE connections are terminated. Clients will need to reconnect (VS Code handles this automatically).

### CPU-based autoscaling

Base HPA configuration:

```yaml
# k8s/base/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: mcp-prometheus
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: mcp-prometheus
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70  # Scale up when CPU > 70%
```

### Memory-based autoscaling

```yaml
metrics:
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80  # Scale up when memory > 80%
```

### Custom metrics autoscaling

Scale based on active SSE connections (requires Prometheus adapter):

```yaml
metrics:
  - type: Pods
    pods:
      metric:
        name: http_connections_active
      target:
        type: AverageValue
        averageValue: 30  # Scale up when avg connections per pod > 30
```

**Setup Prometheus adapter:**
```bash
# Install prometheus-adapter
helm install prometheus-adapter prometheus-community/prometheus-adapter \
  --set prometheus.url=http://prometheus.monitoring:9090

# Configure custom metrics
# values.yaml for prometheus-adapter
rules:
  custom:
    - seriesQuery: 'http_connections_active{namespace="mcp-prometheus-prod"}'
      resources:
        overrides:
          namespace: {resource: "namespace"}
          pod: {resource: "pod"}
      name:
        matches: "^(.*)$"
        as: "${1}"
      metricsQuery: 'sum(<<.Series>>{<<.LabelMatchers>>}) by (<<.GroupBy>>)'
```

### HPA tuning and behavior

The prod HPA includes advanced behavior controls:

```yaml
# k8s/overlays/prod/hpa-patch.yaml
spec:
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300   # Wait 5 min before scaling down
      policies:
        - type: Pods
          value: 1                      # Remove max 1 pod at a time
          periodSeconds: 120            # Wait 2 min between scale-downs
    scaleUp:
      stabilizationWindowSeconds: 60    # Wait 1 min before scaling up
      policies:
        - type: Pods
          value: 2                      # Add max 2 pods at a time
          periodSeconds: 60             # Every 60 seconds
```

**Why these settings matter for SSE:**
- **Slow scale-down** prevents killing SSE connections too aggressively
- **Fast scale-up** handles traffic spikes quickly
- **Stabilization windows** prevent flapping

---

## Intermediate: Per-Environment Scaling

### Dev environment

Minimal resources for development and testing:

```yaml
# HPA: 1-2 replicas
minReplicas: 1
maxReplicas: 2

# Resources per pod
requests:
  cpu: 50m
  memory: 64Mi
limits:
  cpu: 250m
  memory: 128Mi
```

### Perf environment

Moderate resources for performance testing:

```yaml
# HPA: 2-8 replicas
minReplicas: 2
maxReplicas: 8

# Resources per pod
requests:
  cpu: 250m
  memory: 256Mi
limits:
  cpu: "1"
  memory: 512Mi

# Topology spread — distribute across hosts
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
```

### Prod environment

High availability with conservative scaling:

```yaml
# HPA: 3-10 replicas
minReplicas: 3
maxReplicas: 10

# Resources per pod
requests:
  cpu: 500m
  memory: 512Mi
limits:
  cpu: "2"
  memory: "1Gi"

# Spread across zones AND hosts
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway

# PDB — always keep at least 2 pods
minAvailable: 2

# Slow scale-down to protect SSE connections
behavior:
  scaleDown:
    stabilizationWindowSeconds: 300
```

### Environment comparison

| Setting | Dev | Perf | Prod |
|---------|-----|------|------|
| Min replicas | 1 | 2 | 3 |
| Max replicas | 2 | 8 | 10 |
| CPU request | 50m | 250m | 500m |
| CPU limit | 250m | 1 core | 2 cores |
| Memory request | 64Mi | 256Mi | 512Mi |
| Memory limit | 128Mi | 512Mi | 1Gi |
| HPA CPU target | 70% | 60% | 60% |
| HPA memory target | 80% | 70% | 70% |
| Scale-down window | default | default | 5 min |
| PDB | none | none | minAvailable: 2 |
| Anti-affinity | none | hostname | zone + hostname |

---

## Intermediate: Resource Requests and Limits

### Setting the right requests

Requests determine scheduling — Kubernetes uses them to place pods on nodes.

**How to determine:**
1. Deploy with generous limits and no requests
2. Monitor actual usage for 24-48 hours
3. Set requests to the P50 (median) usage
4. Set limits to the P99 usage

```bash
# Monitor CPU usage over time
kubectl top pod -n mcp-prometheus-prod --containers

# Or query Prometheus
# P50 CPU
histogram_quantile(0.50, rate(container_cpu_usage_seconds_total{pod=~"mcp-prometheus.*"}[1h]))

# P99 CPU
histogram_quantile(0.99, rate(container_cpu_usage_seconds_total{pod=~"mcp-prometheus.*"}[1h]))
```

### Setting the right limits

| Scenario | CPU Limit | Memory Limit |
|----------|-----------|--------------|
| Light usage (< 10 users) | 250m | 128Mi |
| Medium usage (10-30 users) | 1 core | 512Mi |
| Heavy usage (30-100 users) | 2 cores | 1Gi |
| Very heavy (complex PromQL) | 4 cores | 2Gi |

### Quality of Service (QoS) classes

| QoS Class | When Applied | Behavior |
|-----------|-------------|----------|
| Guaranteed | requests == limits | Highest priority, never evicted for resources |
| Burstable | requests < limits | Medium priority, may be evicted |
| BestEffort | No requests or limits | Lowest priority, first to be evicted |

**Recommendation:** Use **Burstable** for dev/perf, **Guaranteed** for prod:

```yaml
# Guaranteed (prod) — requests equal limits
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

### Vertical Pod Autoscaler (VPA)

Let Kubernetes automatically adjust resource requests:

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: mcp-prometheus-vpa
  namespace: mcp-prometheus-prod
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: mcp-prometheus
  updatePolicy:
    updateMode: "Auto"  # or "Off" for recommendations only
  resourcePolicy:
    containerPolicies:
      - containerName: mcp-prometheus
        minAllowed:
          cpu: 100m
          memory: 128Mi
        maxAllowed:
          cpu: 4
          memory: 2Gi
```

**Note:** Do not use VPA and HPA on the same metric (e.g., both on CPU). Use VPA for memory and HPA for CPU, or use VPA in recommendation-only mode.

---

## Advanced: High Availability (HA)

### Pod anti-affinity

Prevent multiple MCP pods from running on the same node:

```yaml
# Soft anti-affinity (prefer different nodes, but allow co-location if needed)
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: mcp-prometheus
          topologyKey: kubernetes.io/hostname
```

```yaml
# Hard anti-affinity (never co-locate — requires enough nodes)
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: mcp-prometheus
        topologyKey: kubernetes.io/hostname
```

### Topology spread constraints

Distribute pods evenly across zones and nodes:

```yaml
# Already configured in prod
topologySpreadConstraints:
  # Spread across availability zones (hard requirement)
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: mcp-prometheus
  # Spread across nodes (soft preference)
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: mcp-prometheus
```

### PodDisruptionBudget

Prevent too many pods from being disrupted during upgrades or node maintenance:

```yaml
# Already configured in prod (k8s/overlays/prod/pdb.yaml)
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: mcp-prometheus
spec:
  minAvailable: 2  # Always keep at least 2 pods running
  selector:
    matchLabels:
      app.kubernetes.io/name: mcp-prometheus
```

**Alternative — maxUnavailable:**
```yaml
spec:
  maxUnavailable: 1  # At most 1 pod can be unavailable
```

### Multi-zone deployment

For AKS, ensure your node pool spans multiple availability zones:

```bash
# Check node zones
kubectl get nodes -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.'topology\.kubernetes\.io/zone'

# Create multi-zone node pool
az aks nodepool add \
  --resource-group myResourceGroup \
  --cluster-name myAKSCluster \
  --name mcppool \
  --node-count 3 \
  --zones 1 2 3
```

---

## Advanced: SSE Connection Scaling

### Understanding SSE connection lifecycle

```
Client connects    →  SSE connection established (long-lived)
Client sends query →  Request processed on same connection
Client disconnects →  Connection closed, resources freed
Pod scales down    →  Active connections terminated, clients reconnect
```

**Key insight:** Each SSE connection is persistent. Unlike HTTP request/response, you can't just round-robin requests across pods. A client stays connected to one pod for the lifetime of the connection.

### Connection limits per pod

Estimate max connections per pod based on resources:

| Pod Resources | Max Connections (estimate) |
|---|---|
| 250m CPU, 128Mi | ~20 |
| 500m CPU, 256Mi | ~50 |
| 1 core, 512Mi | ~100 |
| 2 cores, 1Gi | ~200 |

### Load balancer sticky sessions

For proper SSE load balancing, use session affinity:

```yaml
# service.yaml — add session affinity
apiVersion: v1
kind: Service
metadata:
  name: mcp-prometheus
spec:
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 3600  # 1 hour
```

Or at the ingress level:
```yaml
annotations:
  nginx.ingress.kubernetes.io/affinity: "cookie"
  nginx.ingress.kubernetes.io/session-cookie-name: "mcp-sticky"
  nginx.ingress.kubernetes.io/session-cookie-expires: "3600"
```

### Connection draining on scale-down

Ensure graceful shutdown when pods are removed:

```yaml
# deployment.yaml
spec:
  template:
    spec:
      terminationGracePeriodSeconds: 60  # Give 60s for connections to drain
```

The prod deployment uses `rollingUpdate.maxUnavailable: 0` which means Kubernetes always starts a new pod before terminating an old one.

---

## Advanced: Multi-Tenant Scaling

### Shared server scaling

One MCP server pool serving multiple tenants:

```
All tenants → Service → Pod 1, Pod 2, Pod 3 (shared)
```

**Scale based on total query load:**
```yaml
metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
```

### Dedicated server per tenant

Each tenant gets its own deployment and HPA:

```
Tenant A → Service A → Pod A1, Pod A2
Tenant B → Service B → Pod B1, Pod B2
Tenant C → Service C → Pod C1
```

```yaml
# Per-tenant deployment (example for tenant-alpha)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mcp-prometheus-alpha
  namespace: mcp-prometheus-prod
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: mcp-prometheus
          env:
            - name: PROMETHEUS_ORGID
              value: "tenant-alpha"
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: mcp-prometheus-alpha
spec:
  scaleTargetRef:
    kind: Deployment
    name: mcp-prometheus-alpha
  minReplicas: 1
  maxReplicas: 5
```

### Tenant-aware autoscaling

Scale each tenant independently based on their usage:

| Tenant | Users | Min Replicas | Max Replicas | CPU Target |
|--------|-------|-------------|-------------|------------|
| Platform | 50 | 3 | 10 | 60% |
| Dev Team | 10 | 1 | 3 | 70% |
| SRE | 5 | 2 | 5 | 60% |

---

## Advanced: Cluster Autoscaling (AKS)

### Node pool autoscaling

When HPA needs more pods than available nodes can support:

```bash
# Enable cluster autoscaler
az aks update \
  --resource-group myResourceGroup \
  --name myAKSCluster \
  --enable-cluster-autoscaler \
  --min-count 2 \
  --max-count 10

# Or for a specific node pool
az aks nodepool update \
  --resource-group myResourceGroup \
  --cluster-name myAKSCluster \
  --name mcppool \
  --enable-cluster-autoscaler \
  --min-count 2 \
  --max-count 10
```

### Spot instances for cost optimization

Use spot instances for dev/perf to reduce costs:

```bash
# Create spot node pool
az aks nodepool add \
  --resource-group myResourceGroup \
  --cluster-name myAKSCluster \
  --name mcpspot \
  --priority Spot \
  --eviction-policy Delete \
  --spot-max-price -1 \
  --node-count 2 \
  --min-count 1 \
  --max-count 5 \
  --enable-cluster-autoscaler
```

```yaml
# deployment — tolerate spot instances
spec:
  template:
    spec:
      tolerations:
        - key: "kubernetes.azure.com/scalesetpriority"
          operator: "Equal"
          value: "spot"
          effect: "NoSchedule"
      nodeSelector:
        "kubernetes.azure.com/scalesetpriority": "spot"
```

**Do not use spot for prod** — spot instances can be evicted at any time.

### Node selectors and taints

Dedicate specific nodes for MCP workloads:

```bash
# Label nodes
kubectl label nodes <node-name> workload=mcp

# Taint nodes (only MCP pods can run here)
kubectl taint nodes <node-name> workload=mcp:NoSchedule
```

```yaml
# deployment — select and tolerate
spec:
  template:
    spec:
      nodeSelector:
        workload: mcp
      tolerations:
        - key: "workload"
          operator: "Equal"
          value: "mcp"
          effect: "NoSchedule"
```

---

## Advanced: Performance Tuning

### Optimizing Prometheus queries

The biggest scaling factor is query complexity. Optimize queries at the source:

| Issue | Fix |
|-------|-----|
| Queries returning 10K+ series | Add label filters to narrow scope |
| `{__name__=~".+"}` (all metrics) | Use `list_label_values` instead |
| Long range queries (30d+) | Use recording rules in Prometheus |
| Heavy regex matchers | Use exact matchers where possible |
| rate() over long ranges | Use shorter ranges with recording rules |

### Connection pooling

The MCP server maintains HTTP connections to Prometheus. For high throughput:

```bash
# Increase connection pool (if supported by the binary)
# Check available flags
docker exec mcp-prometheus mcp-prometheus serve --help
```

### Ingress tuning for SSE

SSE requires specific ingress configuration for scaling:

```yaml
# ingress annotations (already in base/)
annotations:
  nginx.ingress.kubernetes.io/proxy-buffering: "off"
  nginx.ingress.kubernetes.io/proxy-cache: "off"
  nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
  nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
  # Increase connection limits for high concurrency
  nginx.ingress.kubernetes.io/proxy-connect-timeout: "60"
  nginx.ingress.kubernetes.io/upstream-keepalive-connections: "100"
```

### Kernel tuning for high connections

For nodes handling many SSE connections:

```yaml
# daemonset or init container to tune kernel
initContainers:
  - name: sysctl
    image: busybox
    securityContext:
      privileged: true
    command:
      - sh
      - -c
      - |
        sysctl -w net.core.somaxconn=65535
        sysctl -w net.ipv4.tcp_max_syn_backlog=65535
        sysctl -w net.ipv4.ip_local_port_range="1024 65535"
```

---

## Monitoring Scaling Health

### Key metrics to watch

```bash
# Current replica count vs desired
kubectl get hpa -n mcp-prometheus-<env>

# Pod resource usage
kubectl top pods -n mcp-prometheus-<env>

# Node resource usage
kubectl top nodes
```

### Prometheus queries for scaling decisions

```promql
# CPU usage per pod (should stay below HPA target)
rate(container_cpu_usage_seconds_total{pod=~"mcp-prometheus.*"}[5m])

# Memory usage per pod
container_memory_working_set_bytes{pod=~"mcp-prometheus.*"}

# HPA current vs desired replicas
kube_horizontalpodautoscaler_status_current_replicas{horizontalpodautoscaler="mcp-prometheus"}
kube_horizontalpodautoscaler_status_desired_replicas{horizontalpodautoscaler="mcp-prometheus"}

# Pod restarts (scaling instability indicator)
kube_pod_container_status_restarts_total{container="mcp-prometheus"}

# Active connections (if exposed by the binary)
http_connections_active{job="mcp-prometheus"}
```

### Alerts for scaling issues

```yaml
groups:
  - name: mcp-scaling
    rules:
      - alert: MCPHPAMaxedOut
        expr: |
          kube_horizontalpodautoscaler_status_current_replicas{horizontalpodautoscaler="mcp-prometheus"}
          == kube_horizontalpodautoscaler_spec_max_replicas{horizontalpodautoscaler="mcp-prometheus"}
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "MCP HPA at max replicas for 15 minutes — consider increasing maxReplicas"

      - alert: MCPHighCPU
        expr: rate(container_cpu_usage_seconds_total{pod=~"mcp-prometheus.*"}[5m]) > 0.9
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "MCP pod CPU above 90% for 10 minutes"

      - alert: MCPHighMemory
        expr: container_memory_working_set_bytes{pod=~"mcp-prometheus.*"} / container_spec_memory_limit_bytes > 0.9
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "MCP pod memory above 90% of limit — OOMKill risk"
```

---

## Scaling Decision Matrix

| Situation | Action |
|-----------|--------|
| Single user, local dev | 1 Docker container, no scaling needed |
| Small team (< 10), shared Prometheus | 1-2 Docker containers or Dev K8s overlay |
| Medium team (10-50), moderate queries | Perf K8s overlay with HPA 2-8 |
| Large org (50-200), multiple tenants | Prod K8s overlay with HPA 3-10, per-tenant instances |
| Enterprise (200+), HA required | Prod overlay + cluster autoscaler + multi-zone + spot for non-prod |
| Queries timing out | Vertical scale (more CPU/memory per pod) |
| Many idle connections | Horizontal scale (more pods) |
| Mixed heavy and light queries | Separate heavy-query pool with more resources |
| Cost is a concern | Spot instances for dev/perf, VPA for right-sizing |

---

## Cost Optimization

### Right-sizing with VPA recommendations

```bash
# Install VPA in recommendation mode
# Then check recommendations
kubectl describe vpa mcp-prometheus-vpa -n mcp-prometheus-prod
```

### Cost comparison by environment

| Environment | Est. Monthly Cost (AKS) | Optimization |
|---|---|---|
| Dev (1 pod, 50m/64Mi) | ~$5 | Use spot instances |
| Perf (2 pods, 250m/256Mi) | ~$25 | Use spot instances |
| Prod (3 pods, 500m/512Mi) | ~$80 | Right-size with VPA, scale-to-zero off-hours |

### Scale-to-zero for non-production

Use KEDA for scale-to-zero when no one is connected:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: mcp-prometheus-scaledobject
  namespace: mcp-prometheus-dev
spec:
  scaleTargetRef:
    name: mcp-prometheus
  minReplicaCount: 0
  maxReplicaCount: 2
  triggers:
    - type: prometheus
      metadata:
        serverAddress: http://prometheus.monitoring:9090
        metricName: http_connections_active
        query: 'sum(http_connections_active{namespace="mcp-prometheus-dev"})'
        threshold: "1"
```

This scales the dev environment to zero pods when no one is connected, saving costs.
