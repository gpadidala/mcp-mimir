# MCP Prometheus Server — Security & Access Control Guide

A comprehensive security guide covering authentication, authorization, network isolation, secrets management, and advanced access control for Docker and Kubernetes deployments.

## Table of Contents

1. [Security Overview](#security-overview)
2. [Basic: Authentication Methods](#basic-authentication-methods)
   - [No authentication (local development)](#no-authentication-local-development)
   - [Basic authentication (username/password)](#basic-authentication-usernamepassword)
   - [Bearer token authentication](#bearer-token-authentication)
   - [Choosing the right method](#choosing-the-right-method)
3. [Basic: Securing the Docker Deployment](#basic-securing-the-docker-deployment)
   - [Bind to localhost only](#bind-to-localhost-only)
   - [Protect the .env file](#protect-the-env-file)
   - [Run as non-root user](#run-as-non-root-user)
   - [Read-only filesystem](#read-only-filesystem)
4. [Basic: Multi-Tenancy Access Control](#basic-multi-tenancy-access-control)
   - [Single-tenant setup](#single-tenant-setup)
   - [Per-request org ID override](#per-request-org-id-override)
   - [Dedicated server per tenant](#dedicated-server-per-tenant)
5. [Intermediate: Network Security](#intermediate-network-security)
   - [Docker network isolation](#docker-network-isolation)
   - [Firewall rules](#firewall-rules)
   - [Reverse proxy with authentication](#reverse-proxy-with-authentication)
   - [IP allowlisting](#ip-allowlisting)
6. [Intermediate: Secrets Management](#intermediate-secrets-management)
   - [Docker secrets](#docker-secrets)
   - [Kubernetes secrets](#kubernetes-secrets)
   - [Azure Key Vault integration](#azure-key-vault-integration)
   - [Rotating credentials](#rotating-credentials)
7. [Intermediate: VS Code Client Security](#intermediate-vs-code-client-security)
   - [Securing the SSE connection](#securing-the-sse-connection)
   - [Org ID header injection](#org-id-header-injection)
   - [Restricting MCP tool access](#restricting-mcp-tool-access)
8. [Advanced: Kubernetes RBAC & Pod Security](#advanced-kubernetes-rbac--pod-security)
   - [Service account least privilege](#service-account-least-privilege)
   - [Pod security standards](#pod-security-standards)
   - [Security context configuration](#security-context-configuration)
   - [Role-based access to MCP endpoints](#role-based-access-to-mcp-endpoints)
9. [Advanced: Network Policies (Kubernetes)](#advanced-network-policies-kubernetes)
   - [Ingress rules](#ingress-rules)
   - [Egress rules](#egress-rules)
   - [Per-environment network policies](#per-environment-network-policies)
   - [Zero-trust networking](#zero-trust-networking)
10. [Advanced: TLS / mTLS Encryption](#advanced-tls--mtls-encryption)
    - [TLS termination at ingress](#tls-termination-at-ingress)
    - [End-to-end TLS](#end-to-end-tls)
    - [Mutual TLS (mTLS) with service mesh](#mutual-tls-mtls-with-service-mesh)
    - [Certificate management with cert-manager](#certificate-management-with-cert-manager)
11. [Advanced: Rate Limiting & DDoS Protection](#advanced-rate-limiting--ddos-protection)
    - [NGINX ingress rate limiting](#nginx-ingress-rate-limiting)
    - [Connection limits](#connection-limits)
    - [Per-client rate limiting](#per-client-rate-limiting)
12. [Advanced: Audit Logging & Monitoring](#advanced-audit-logging--monitoring)
    - [Access logging](#access-logging)
    - [Query auditing](#query-auditing)
    - [Security alerts](#security-alerts)
    - [Compliance monitoring](#compliance-monitoring)
13. [Advanced: Image Security](#advanced-image-security)
    - [Image scanning](#image-scanning)
    - [Image signing](#image-signing)
    - [Private registry lockdown](#private-registry-lockdown)
14. [Security Hardening Checklist](#security-hardening-checklist)
15. [Threat Model](#threat-model)

---

## Security Overview

The MCP Prometheus server acts as a **read-only bridge** between AI assistants and your Prometheus/Mimir metrics. While all 18 MCP tools are read-only (no writes to Prometheus), the data exposed can include sensitive infrastructure details, so proper security is essential.

### Attack surface

```
VS Code / AI Client
       |
       | (1) SSE Connection — who can connect?
       |
MCP Prometheus Server
       |
       | (2) Prometheus Auth — how does the server authenticate?
       |
Prometheus / Mimir
       |
       | (3) Metric Data — what data is exposed?
       v
```

**Security layers to consider:**
1. **Who can connect to the MCP server** — network access, authentication
2. **How the MCP server connects to Prometheus** — credentials, encryption
3. **What data is exposed** — tenant isolation, query filtering

---

## Basic: Authentication Methods

### No authentication (local development)

For local development only. The MCP server is accessible to anyone who can reach port 8080.

```bash
# .env — no auth settings
PROMETHEUS_URL=http://host.docker.internal:9090
```

**Risk:** Anyone on the same network can connect and query your metrics.

**When to use:** Local development with Docker Desktop, no sensitive data.

### Basic authentication (username/password)

The MCP server sends `Authorization: Basic <base64>` to Prometheus.

```bash
# .env
PROMETHEUS_USERNAME=mcp-reader
PROMETHEUS_PASSWORD=strong-random-password-here
```

**Verify it works:**
```bash
# Test directly against Prometheus
curl -u mcp-reader:strong-random-password-here \
  http://<prometheus-url>/api/v1/query?query=up

# Test from inside the container
docker exec mcp-prometheus sh -c 'wget -qO- $PROMETHEUS_URL/api/v1/status/buildinfo'
```

**Best practices:**
- Use a dedicated read-only service account, not a personal account
- Generate a strong random password: `openssl rand -base64 32`
- Never commit passwords to git — use `.env` (which is in `.gitignore`)

### Bearer token authentication

For Prometheus/Mimir setups that use token-based auth (OAuth2, API keys).

```bash
# .env
PROMETHEUS_TOKEN=eyJhbGciOiJSUzI1NiIs...
```

**Verify:**
```bash
curl -H "Authorization: Bearer eyJhbGciOiJSUzI1NiIs..." \
  http://<prometheus-url>/api/v1/query?query=up
```

**Best practices:**
- Use short-lived tokens where possible
- Rotate tokens regularly (see [Rotating credentials](#rotating-credentials))
- Use scoped tokens with read-only permissions

### Choosing the right method

| Scenario | Method | Notes |
|----------|--------|-------|
| Local dev, no sensitive data | None | Bind to localhost only |
| Prometheus with basic auth | Basic auth | Dedicated read-only user |
| Mimir with API gateway | Bearer token | Scoped read-only token |
| Kubernetes with service mesh | mTLS | No credentials needed |
| Enterprise with SSO | Bearer token | From OAuth2/OIDC flow |

---

## Basic: Securing the Docker Deployment

### Bind to localhost only

Prevent the MCP server from being accessible outside your machine.

```yaml
# docker-compose.yml — bind to localhost
ports:
  - "127.0.0.1:8080:8080"
  - "127.0.0.1:9091:9091"
```

Or in `.env`:
```bash
MCP_PORT=127.0.0.1:8080
METRICS_PORT=127.0.0.1:9091
```

**Verify:**
```bash
# Should work
curl http://localhost:8080/sse

# Should NOT work from another machine
curl http://<your-ip>:8080/sse  # Connection refused
```

### Protect the .env file

The `.env` file may contain credentials. Secure it:

```bash
# Restrict file permissions (owner read/write only)
chmod 600 .env

# Ensure .env is in .gitignore
echo ".env" >> .gitignore

# Verify it's not tracked by git
git status .env  # Should show as untracked or not listed
```

### Run as non-root user

The Dockerfile already configures a non-root user in Kubernetes. For Docker:

```yaml
# docker-compose.yml — add user directive
services:
  mcp-prometheus:
    user: "65534:65534"  # nobody:nobody
    # ... rest of config
```

### Read-only filesystem

Prevent the container from writing to the filesystem:

```yaml
# docker-compose.yml
services:
  mcp-prometheus:
    read_only: true
    tmpfs:
      - /tmp  # If the binary needs temp space
    # ... rest of config
```

---

## Basic: Multi-Tenancy Access Control

### Single-tenant setup

One MCP server serves one tenant. All queries go to the same org.

```bash
# .env
PROMETHEUS_ORGID=my-team
```

Every query automatically includes `X-Scope-OrgID: my-team`.

### Per-request org ID override

Users can override the org ID per-query via the MCP tool:

```json
{ "name": "execute_query", "arguments": { "query": "up", "org_id": "other-team" } }
```

**Risk:** Users can access any tenant's data if they know the org ID.

**Mitigation:** Use dedicated MCP server instances per tenant (see below).

### Dedicated server per tenant

Run isolated MCP servers, each locked to one tenant:

```yaml
# docker-compose.yml
services:
  mcp-team-alpha:
    image: mcp-prometheus:latest
    ports:
      - "8081:8080"
    environment:
      - PROMETHEUS_URL=http://host.docker.internal:9090
      - PROMETHEUS_ORGID=team-alpha

  mcp-team-beta:
    image: mcp-prometheus:latest
    ports:
      - "8082:8080"
    environment:
      - PROMETHEUS_URL=http://host.docker.internal:9090
      - PROMETHEUS_ORGID=team-beta
```

**VS Code config per team:**
```json
{
  "servers": {
    "mcp-team-alpha": {
      "type": "sse",
      "url": "http://localhost:8081/sse"
    }
  }
}
```

**This is the most secure multi-tenant approach** — users can only access their assigned tenant.

---

## Intermediate: Network Security

### Docker network isolation

Create an isolated Docker network so only the MCP server can reach Prometheus:

```yaml
# docker-compose.yml
services:
  mcp-prometheus:
    networks:
      - mcp-internal
    # ... rest of config

networks:
  mcp-internal:
    driver: bridge
    internal: false  # Set to true to block all external access
```

### Firewall rules

Restrict access to the MCP server at the OS level:

```bash
# Linux (iptables) — only allow localhost
iptables -A INPUT -p tcp --dport 8080 -s 127.0.0.1 -j ACCEPT
iptables -A INPUT -p tcp --dport 8080 -j DROP

# macOS (pf) — only allow localhost
echo "block in proto tcp from any to any port 8080" | sudo pfctl -ef -
```

### Reverse proxy with authentication

Put NGINX in front of the MCP server to add authentication:

```nginx
# nginx.conf
server {
    listen 443 ssl;
    server_name mcp.internal;

    ssl_certificate /etc/ssl/certs/mcp.crt;
    ssl_certificate_key /etc/ssl/private/mcp.key;

    # Basic auth for MCP clients
    auth_basic "MCP Access";
    auth_basic_user_file /etc/nginx/.htpasswd;

    # SSE-specific settings
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 86400s;
    proxy_send_timeout 86400s;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Connection '';
        proxy_http_version 1.1;
        chunked_transfer_encoding off;
    }
}
```

**Create htpasswd file:**
```bash
htpasswd -c /etc/nginx/.htpasswd mcp-user
```

### IP allowlisting

Restrict which IPs can access the MCP server:

```nginx
# nginx.conf — add to server block
allow 10.0.0.0/8;       # Internal network
allow 192.168.1.0/24;   # Office network
deny all;
```

---

## Intermediate: Secrets Management

### Docker secrets

Use Docker secrets instead of environment variables for credentials:

```yaml
# docker-compose.yml
services:
  mcp-prometheus:
    secrets:
      - prometheus_password
      - prometheus_token
    environment:
      - PROMETHEUS_PASSWORD_FILE=/run/secrets/prometheus_password
      - PROMETHEUS_TOKEN_FILE=/run/secrets/prometheus_token

secrets:
  prometheus_password:
    file: ./secrets/prometheus_password.txt
  prometheus_token:
    file: ./secrets/prometheus_token.txt
```

**Note:** This requires the `mcp-prometheus` binary to support `_FILE` env vars. If it doesn't, use an entrypoint script to read the files:

```bash
# entrypoint.sh
export PROMETHEUS_PASSWORD=$(cat /run/secrets/prometheus_password)
exec mcp-prometheus serve --transport "$TRANSPORT" --http-addr "$HTTP_ADDR" --metrics-addr "$METRICS_ADDR"
```

### Kubernetes secrets

The base manifests already use Kubernetes secrets:

```bash
# Create secret from literal values
kubectl create secret generic mcp-prometheus-secret \
  -n mcp-prometheus-prod \
  --from-literal=PROMETHEUS_USERNAME=mcp-reader \
  --from-literal=PROMETHEUS_PASSWORD=$(openssl rand -base64 32) \
  --from-literal=PROMETHEUS_TOKEN=""

# Or create from a file
kubectl create secret generic mcp-prometheus-secret \
  -n mcp-prometheus-prod \
  --from-file=PROMETHEUS_PASSWORD=./secrets/password.txt
```

**Encrypt secrets at rest:**
```bash
# AKS — enable encryption at rest (enabled by default in AKS)
az aks update -g myResourceGroup -n myAKSCluster --enable-encryption-at-host
```

### Azure Key Vault integration

Use Azure Key Vault with CSI driver for production secrets:

```yaml
# secret-provider-class.yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: mcp-prometheus-secrets
  namespace: mcp-prometheus-prod
spec:
  provider: azure
  parameters:
    usePodIdentity: "true"
    keyvaultName: "my-keyvault"
    objects: |
      array:
        - |
          objectName: prometheus-username
          objectType: secret
        - |
          objectName: prometheus-password
          objectType: secret
        - |
          objectName: prometheus-token
          objectType: secret
    tenantId: "<azure-tenant-id>"
  secretObjects:
    - secretName: mcp-prometheus-secret
      type: Opaque
      data:
        - objectName: prometheus-username
          key: PROMETHEUS_USERNAME
        - objectName: prometheus-password
          key: PROMETHEUS_PASSWORD
        - objectName: prometheus-token
          key: PROMETHEUS_TOKEN
```

```yaml
# Add to deployment pod spec
volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: mcp-prometheus-secrets
```

### Rotating credentials

**Manual rotation (Docker):**
```bash
# 1. Update .env with new credentials
vim .env

# 2. Restart the container
docker compose restart
```

**Manual rotation (Kubernetes):**
```bash
# 1. Update the secret
kubectl create secret generic mcp-prometheus-secret \
  -n mcp-prometheus-prod \
  --from-literal=PROMETHEUS_PASSWORD=new-password \
  --dry-run=client -o yaml | kubectl apply -f -

# 2. Restart the pods to pick up new secret
kubectl rollout restart deployment/mcp-prometheus -n mcp-prometheus-prod
```

**Automated rotation with Azure Key Vault:**
- Set rotation policies in Key Vault
- CSI driver auto-syncs secrets (poll interval configurable)
- Use `rotation-poll-interval` annotation in SecretProviderClass

---

## Intermediate: VS Code Client Security

### Securing the SSE connection

When connecting VS Code to a remote MCP server:

1. **Always use HTTPS** for remote connections (see [TLS section](#advanced-tls--mtls-encryption))
2. **Use a VPN or SSH tunnel** if HTTPS is not available:
   ```bash
   # SSH tunnel — forward local 8080 to remote MCP server
   ssh -L 8080:localhost:8080 user@remote-server
   # Then connect VS Code to http://localhost:8080/sse
   ```

### Org ID header injection

The `.vscode/mcp.json` sends `X-Scope-OrgID` as a header:

```json
{
  "servers": {
    "mcp-prometheus": {
      "type": "sse",
      "url": "http://localhost:8080/sse",
      "headers": {
        "X-Scope-OrgID": "my-team"
      }
    }
  }
}
```

**Risk:** This header can be modified by the user. For strict tenant isolation, use dedicated MCP server instances per tenant.

### Restricting MCP tool access

The MCP server exposes all 18 tools. If you want to limit which tools are available:

1. **Use a reverse proxy** to filter requests by tool name
2. **Use separate MCP servers** with different configurations per team
3. **Monitor tool usage** via access logs (see [Audit Logging](#advanced-audit-logging--monitoring))

---

## Advanced: Kubernetes RBAC & Pod Security

### Service account least privilege

The MCP server pod should use a dedicated service account with no Kubernetes API permissions:

```yaml
# serviceaccount.yaml (already in base/)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: mcp-prometheus
automountServiceAccountToken: false  # Add this — no K8s API access needed
```

### Pod security standards

Apply Kubernetes Pod Security Standards:

```yaml
# namespace.yaml — enforce restricted standard
apiVersion: v1
kind: Namespace
metadata:
  name: mcp-prometheus-prod
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Security context configuration

The prod deployment already has hardened security context:

```yaml
# Already configured in prod deployment-patch.yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL

# Pod-level (in base/deployment.yaml)
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    runAsGroup: 65534
    fsGroup: 65534
```

**Additional hardening:**
```yaml
# Add to container securityContext
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault
  capabilities:
    drop:
      - ALL
```

### Role-based access to MCP endpoints

Use Kubernetes RBAC to control who can port-forward or access the MCP service:

```yaml
# rbac.yaml — restrict port-forward to specific users
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: mcp-prometheus-access
  namespace: mcp-prometheus-prod
rules:
  - apiGroups: [""]
    resources: ["pods/portforward"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["services/proxy"]
    verbs: ["get"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: mcp-prometheus-access
  namespace: mcp-prometheus-prod
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: mcp-prometheus-access
subjects:
  - kind: Group
    name: sre-team
    apiGroup: rbac.authorization.k8s.io
```

---

## Advanced: Network Policies (Kubernetes)

### Ingress rules

The prod NetworkPolicy (already deployed) restricts incoming traffic:

```yaml
# Only allow traffic from ingress controller on port 8080
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: ingress-nginx
    ports:
      - port: 8080
        protocol: TCP
  # Only allow Prometheus scraping on port 9091
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: monitoring
    ports:
      - port: 9091
        protocol: TCP
```

### Egress rules

Restrict outbound traffic to only what's needed:

```yaml
# Only allow DNS and Prometheus/Mimir
egress:
  - to:
      - namespaceSelector: {}
    ports:
      - port: 53
        protocol: UDP
      - port: 53
        protocol: TCP
  - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: mimir-prod
    ports:
      - port: 8080
        protocol: TCP
      - port: 9090
        protocol: TCP
```

### Per-environment network policies

| Environment | Ingress | Egress |
|---|---|---|
| Dev | Open (no NetworkPolicy) | Open |
| Perf | Open | Open |
| Prod | Ingress controller + monitoring only | DNS + Mimir only |

**To add NetworkPolicy to dev/perf:**

```yaml
# k8s/overlays/dev/networkpolicy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mcp-prometheus
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: mcp-prometheus
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector: {}  # Allow all within namespace
      ports:
        - port: 8080
```

### Zero-trust networking

For maximum security, combine NetworkPolicy with a service mesh:

1. **Deny all by default:**
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: deny-all
   spec:
     podSelector: {}
     policyTypes:
       - Ingress
       - Egress
   ```

2. **Explicitly allow only required traffic** (as shown above)

3. **Add mTLS via service mesh** (Istio, Linkerd) for encrypted pod-to-pod communication

---

## Advanced: TLS / mTLS Encryption

### TLS termination at ingress

The prod overlay already configures TLS via cert-manager:

```yaml
# k8s/overlays/prod/ingress-patch.yaml (already configured)
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
    - hosts:
        - mcp-prometheus.aks.internal
      secretName: mcp-prometheus-tls
```

**Setup cert-manager:**
```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

# Create ClusterIssuer
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
```

### End-to-end TLS

For encryption all the way from ingress to pod:

```yaml
# ingress annotation — backend uses HTTPS
metadata:
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
```

This requires the MCP server binary to support TLS. Check upstream documentation.

### Mutual TLS (mTLS) with service mesh

Use Istio or Linkerd for automatic mTLS between all pods:

**Istio:**
```yaml
# PeerAuthentication — require mTLS for the namespace
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: strict-mtls
  namespace: mcp-prometheus-prod
spec:
  mtls:
    mode: STRICT
```

**Linkerd:**
```bash
# Inject Linkerd proxy into the deployment
kubectl get deployment mcp-prometheus -n mcp-prometheus-prod -o yaml | linkerd inject - | kubectl apply -f -
```

### Certificate management with cert-manager

```bash
# Check certificate status
kubectl get certificate -n mcp-prometheus-prod

# Check if cert is about to expire
kubectl get certificate mcp-prometheus-tls -n mcp-prometheus-prod -o jsonpath='{.status.notAfter}'

# Force renewal
kubectl delete certificate mcp-prometheus-tls -n mcp-prometheus-prod
# cert-manager will auto-recreate it
```

---

## Advanced: Rate Limiting & DDoS Protection

### NGINX ingress rate limiting

Already configured in the prod ingress:

```yaml
annotations:
  nginx.ingress.kubernetes.io/limit-rps: "50"          # 50 requests per second
  nginx.ingress.kubernetes.io/limit-connections: "20"   # 20 concurrent connections
```

### Connection limits

SSE connections are long-lived. Limit the total:

```yaml
annotations:
  nginx.ingress.kubernetes.io/limit-connections: "20"
  nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"   # 1 hour max per connection
```

### Per-client rate limiting

Rate limit by client IP:

```yaml
annotations:
  nginx.ingress.kubernetes.io/limit-rps: "10"
  nginx.ingress.kubernetes.io/limit-whitelist: "10.0.0.0/8"  # No limit for internal
```

---

## Advanced: Audit Logging & Monitoring

### Access logging

Enable NGINX access logs for all MCP requests:

```yaml
# ingress annotation
annotations:
  nginx.ingress.kubernetes.io/enable-access-log: "true"
```

**View logs:**
```bash
# NGINX ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx | grep mcp-prometheus
```

### Query auditing

Monitor what queries are being run through the MCP server:

```bash
# Watch MCP server logs for query patterns
kubectl logs -n mcp-prometheus-prod -l app.kubernetes.io/name=mcp-prometheus -f | grep execute_query

# Docker
docker compose logs -f mcp-prometheus | grep execute_query
```

### Security alerts

Create Prometheus alerts for security events:

```yaml
# prometheus-rules.yaml
groups:
  - name: mcp-security
    rules:
      - alert: MCPHighErrorRate
        expr: rate(http_requests_total{job="mcp-prometheus",code=~"4.."}[5m]) > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate on MCP server — possible unauthorized access attempts"

      - alert: MCPTooManyConnections
        expr: http_connections_active{job="mcp-prometheus"} > 50
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Unusual number of active connections to MCP server"

      - alert: MCPUnauthorizedAccess
        expr: rate(http_requests_total{job="mcp-prometheus",code="401"}[5m]) > 5
        for: 3m
        labels:
          severity: critical
        annotations:
          summary: "Multiple 401 responses — possible brute force attempt"
```

### Compliance monitoring

For environments with compliance requirements:

```bash
# Audit Kubernetes API access to the MCP namespace
kubectl get events -n mcp-prometheus-prod --sort-by='.lastTimestamp'

# Check who has access to secrets
kubectl auth can-i get secrets -n mcp-prometheus-prod --as=<user>

# Verify pod security context
kubectl get pod -n mcp-prometheus-prod -o jsonpath='{.items[*].spec.securityContext}'
```

---

## Advanced: Image Security

### Image scanning

Scan the Docker image for vulnerabilities before deploying:

```bash
# Using Trivy
trivy image mcp-prometheus:latest

# Using Azure Defender (ACR)
az acr task create --registry <acr-name> --name scan-mcp \
  --image mcp-prometheus:latest --cmd "trivy image {{.Run.Registry}}/mcp-prometheus:latest"

# Using Docker Scout
docker scout cves mcp-prometheus:latest
```

### Image signing

Sign images before pushing to the registry:

```bash
# Using cosign
cosign sign --key cosign.key $ACR_REGISTRY/mcp-prometheus:v0.0.59

# Verify
cosign verify --key cosign.pub $ACR_REGISTRY/mcp-prometheus:v0.0.59
```

### Private registry lockdown

Restrict image pulls to your private ACR only:

```yaml
# deployment spec
spec:
  containers:
    - name: mcp-prometheus
      image: your-acr.azurecr.io/mcp-prometheus:v0.0.59
      imagePullPolicy: Always
  imagePullSecrets:
    - name: acr-pull-secret
```

**Create pull secret:**
```bash
kubectl create secret docker-registry acr-pull-secret \
  -n mcp-prometheus-prod \
  --docker-server=your-acr.azurecr.io \
  --docker-username=<service-principal-id> \
  --docker-password=<service-principal-password>
```

---

## Security Hardening Checklist

### Docker (Local Development)

- [ ] Bind ports to `127.0.0.1` only
- [ ] `.env` file has `chmod 600` permissions
- [ ] `.env` is in `.gitignore`
- [ ] No credentials committed to git
- [ ] Container runs as non-root user
- [ ] Read-only filesystem enabled
- [ ] Only required ports are exposed (8080, 9091)

### Kubernetes (All Environments)

- [ ] Dedicated service account with no K8s API access
- [ ] `automountServiceAccountToken: false`
- [ ] Non-root user (`runAsNonRoot: true`)
- [ ] Read-only root filesystem
- [ ] All capabilities dropped
- [ ] Resource limits set (prevents resource abuse)
- [ ] Secrets stored in Kubernetes Secrets (not ConfigMap)

### Kubernetes (Production)

- [ ] NetworkPolicy restricting ingress and egress
- [ ] TLS enabled on ingress
- [ ] cert-manager for automated certificate rotation
- [ ] Rate limiting configured on ingress
- [ ] PodDisruptionBudget in place
- [ ] Pod anti-affinity for HA
- [ ] Image pulled from private ACR with pull secrets
- [ ] Image scanning in CI/CD pipeline
- [ ] Pod Security Standards enforced at namespace level
- [ ] Audit logging enabled
- [ ] Security alerts configured in Prometheus

### Access Control

- [ ] Dedicated read-only Prometheus credentials for MCP server
- [ ] Per-tenant MCP server instances (if multi-tenant)
- [ ] RBAC restricting who can port-forward to MCP pods
- [ ] IP allowlisting for ingress (if applicable)
- [ ] Credential rotation procedure documented and tested

---

## Threat Model

| Threat | Risk | Mitigation |
|--------|------|------------|
| Unauthorized access to MCP server | Attacker queries sensitive metrics | Network isolation, auth at ingress, bind to localhost |
| Credential theft from .env | Attacker gets Prometheus credentials | File permissions, Docker secrets, Key Vault |
| Cross-tenant data access | User queries another team's metrics | Dedicated MCP instances per tenant |
| Man-in-the-middle (SSE) | Attacker intercepts metric data | TLS encryption, mTLS |
| Container escape | Attacker gains host access | Non-root, read-only FS, drop all capabilities, seccomp |
| Supply chain attack (image) | Malicious binary injected | Image scanning, signing, pinned versions |
| DDoS on MCP endpoint | Service unavailable | Rate limiting, HPA, connection limits |
| Compromised AI assistant | AI tool sends malicious queries | All 18 tools are read-only, no write access to Prometheus |
| Secret sprawl | Credentials in logs, env dumps | Avoid logging secrets, use `_FILE` patterns, Key Vault |
