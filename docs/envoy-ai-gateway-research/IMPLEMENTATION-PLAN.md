# Envoy AI Gateway Implementation Plan

## Executive Summary

This document outlines the implementation plan for integrating Envoy AI Gateway into the Talos Kubernetes Cluster template. The AI Gateway extends the existing Envoy Gateway deployment with AI/LLM traffic management capabilities.

> **IMPORTANT - v0.4.0 API Changes**: This plan has been updated based on actual deployment experience. See the [Critical v0.4.0 Fixes](#critical-v040-fixes) section for essential corrections to the original API specifications.

## Current State Analysis

### Existing Infrastructure
- **Kubernetes Version**: v1.34.2 ✅ (Requirement: 1.29+)
- **Envoy Gateway Version**: v1.6.0 ✅ (Requirement: 1.5.0+)
- **Envoy Gateway Namespace**: `network`
- **Gateway Configuration**: Two gateways (internal/external) with existing BackendTrafficPolicy and ClientTrafficPolicy

### Gap Analysis

| Requirement | Current | Required | Action |
|-------------|---------|----------|--------|
| Buffer Limit (Backend) | 8Mi | 50Mi+ | Increase |
| Buffer Limit (Client) | 4Mi | 50Mi+ | Increase |
| AI Gateway CRDs | Not installed | Required | Install |
| AI Gateway Controller | Not installed | Required | Install |
| Rate Limit Backend | None | Redis | Deploy |
| MCP Gateway | None | Required | Configure |

## Implementation Phases

### Phase 1: Foundation (Low Risk)

**Objective**: Install AI Gateway CRDs and controller without affecting existing workloads.

> **See Also**: [IMPLEMENTATION-PLAN-ADDENDUM.md](./IMPLEMENTATION-PLAN-ADDENDUM.md) for additional project-wide changes including:
> - GitHub test configurations (`.github/tests/`)
> - CUE schema validation updates
> - Plugin.py data enrichment
> - README.md and CLAUDE.md documentation updates

#### 1.1 Add Configuration Schema

Add to `cluster.schema.cue`:
```cue
ai_gateway_enabled?: bool
ai_gateway_version?: string
ai_gateway_namespace?: string
ai_gateway_addr?: string
ai_gateway_azure_deployments?: [...{
    name: string
    host: string
    api_key: string
    models: [...string]
}]
ai_gateway_mcp_enabled?: bool
ai_gateway_mcp_servers?: [...{
    name: string
    host: string
    path?: string
    api_key?: string
    tool_filter?: [...string]
}]
ai_gateway_ratelimit_enabled?: bool
ai_gateway_ratelimit_default_limit?: int
```

Add to `cluster.sample.yaml`:
```yaml
# ==============================================================================
# ENVOY AI GATEWAY (Optional)
# ==============================================================================
# Configuration for Envoy AI Gateway LLM traffic management.
# REF: https://aigateway.envoyproxy.io/

# -- Enable Envoy AI Gateway for LLM traffic management.
#    (OPTIONAL) / (DEFAULT: false)
# ai_gateway_enabled: false

# -- AI Gateway version (commit hash or release tag).
#    (OPTIONAL) / (DEFAULT: "v0.4.0")
# ai_gateway_version: ""

# -- LoadBalancer IP for AI Gateway service.
#    (OPTIONAL) / (DEFAULT: uses cluster_gateway_addr)
#    TIP: Allocate a dedicated IP for AI workloads if desired.
# ai_gateway_addr: ""

# -- Azure OpenAI deployments configuration.
#    Each deployment represents a different Azure OpenAI resource with its own
#    endpoint and API key. Models are routed based on x-ai-eg-model header.
#    (REQUIRED if ai_gateway_enabled)
#
#    Example:
#    ai_gateway_azure_deployments:
#      - name: "primary"
#        host: "my-resource.openai.azure.com"
#        api_key: "your-api-key-here"
#        models: ["gpt-4", "gpt-4o"]
#      - name: "secondary"
#        host: "my-other-resource.openai.azure.com"
#        api_key: "another-api-key"
#        models: ["gpt-35-turbo", "text-embedding-ada-002"]
# ai_gateway_azure_deployments: []

# -- MCP (Model Context Protocol) gateway support.
#    Enables tool/agent connectivity via MCP servers.
#    (OPTIONAL) / (DEFAULT: false)
# ai_gateway_mcp_enabled: false

# -- MCP server configurations.
#    Each server aggregates into a unified MCP endpoint.
#
#    Example:
#    ai_gateway_mcp_servers:
#      - name: "github"
#        host: "api.githubcopilot.com"
#        path: "/mcp/readonly"
#        api_key: "ghp_xxxxx"
#        tool_filter: [".*issues?.*", ".*pull_requests?.*"]
#      - name: "context7"
#        host: "mcp.context7.io"
#        path: "/mcp"
# ai_gateway_mcp_servers: []

# -- Token-based rate limiting.
#    Deploys Redis for rate limit state storage.
#    (OPTIONAL) / (DEFAULT: false)
# ai_gateway_ratelimit_enabled: false

# -- Default token rate limit per hour per user.
#    (OPTIONAL) / (DEFAULT: 100000)
# ai_gateway_ratelimit_default_limit: 100000
```

#### 1.2 Add Plugin Defaults

Add to `templates/scripts/plugin.py`:
```python
# AI Gateway defaults
data.setdefault("ai_gateway_enabled", False)
data.setdefault("ai_gateway_version", "v0.4.0")
data.setdefault("ai_gateway_namespace", "envoy-ai-gateway-system")
data.setdefault("ai_gateway_addr", data.get("cluster_gateway_addr", ""))
data.setdefault("ai_gateway_azure_deployments", [])
data.setdefault("ai_gateway_mcp_enabled", False)
data.setdefault("ai_gateway_mcp_servers", [])
data.setdefault("ai_gateway_ratelimit_enabled", False)
data.setdefault("ai_gateway_ratelimit_default_limit", 100000)
```

#### 1.3 Create Namespace Template

Create `templates/config/kubernetes/apps/ai-gateway/namespace.yaml.j2`:
```yaml
#% if ai_gateway_enabled %#
---
apiVersion: v1
kind: Namespace
metadata:
  name: envoy-ai-gateway-system
  labels:
    app.kubernetes.io/name: envoy-ai-gateway
#% endif %#
```

#### 1.4 Create CRD HelmRelease Template

Create `templates/config/kubernetes/apps/ai-gateway/crds/`:
- `ks.yaml.j2` - Kustomization
- `app/helmrelease.yaml.j2` - AI Gateway CRDs Helm chart
- `app/ocirepository.yaml.j2` - OCI repository reference
- `app/kustomization.yaml.j2` - Kustomize config

#### 1.5 Create Controller HelmRelease Template

Create `templates/config/kubernetes/apps/ai-gateway/controller/`:
- `ks.yaml.j2` - Kustomization (depends on CRDs)
- `app/helmrelease.yaml.j2` - AI Gateway controller Helm chart
- `app/ocirepository.yaml.j2` - OCI repository reference
- `app/kustomization.yaml.j2` - Kustomize config

### Phase 2: Update Existing Envoy Gateway

**Objective**: Configure Envoy Gateway to support AI Gateway extension processing.

#### 2.1 Update Buffer Limits

Modify `templates/config/kubernetes/apps/network/envoy-gateway/app/envoy.yaml.j2`:

```yaml
# BackendTrafficPolicy - increase buffer
spec:
  connection:
    bufferLimit: #{ '50Mi' if ai_gateway_enabled else '8Mi' }#

# ClientTrafficPolicy - increase buffer
spec:
  connection:
    bufferLimit: #{ '50Mi' if ai_gateway_enabled else '4Mi' }#
```

#### 2.2 Add AI Gateway Values to Envoy Gateway HelmRelease

Update `templates/config/kubernetes/apps/network/envoy-gateway/app/helmrelease.yaml.j2`:

```yaml
values:
  config:
    envoyGateway:
      provider:
        type: Kubernetes
        kubernetes:
          deploy:
            type: GatewayNamespace
#% if ai_gateway_enabled %#
      # Extension server for AI Gateway
      extensionManager:
        backendResources:
          - group: gateway.envoyproxy.io
            kind: BackendTrafficPolicy
            version: v1alpha1
#% if ai_gateway_ratelimit_enabled %#
      rateLimit:
        backend:
          type: Redis
          redis:
            url: redis.envoy-ai-gateway-system.svc:6379
#% endif %#
#% endif %#
```

### Phase 3: Azure OpenAI Provider Backends

**Objective**: Configure multiple Azure OpenAI deployments with model-based routing.

#### 3.1 Azure OpenAI Backend (Primary Provider)

Create `templates/config/kubernetes/apps/ai-gateway/backends/azure-openai/`:

**secret.sops.yaml.j2**:
```yaml
#% if ai_gateway_enabled and ai_gateway_azure_deployments %#
#% for deployment in ai_gateway_azure_deployments %#
---
apiVersion: v1
kind: Secret
metadata:
  name: azure-openai-#{ deployment.name }#-credentials
  namespace: envoy-ai-gateway-system
type: Opaque
stringData:
  client-secret: #{ deployment.api_key }#
#% endfor %#
#% endif %#
```

**backend.yaml.j2**:
```yaml
#% if ai_gateway_enabled and ai_gateway_azure_deployments %#
#% for deployment in ai_gateway_azure_deployments %#
---
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: BackendSecurityPolicy
metadata:
  name: azure-openai-#{ deployment.name }#-auth
  namespace: envoy-ai-gateway-system
spec:
  type: APIKey
  apiKey:
    secretRef:
      name: azure-openai-#{ deployment.name }#-credentials
      key: client-secret
---
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: AIServiceBackend
metadata:
  name: azure-openai-#{ deployment.name }#
  namespace: envoy-ai-gateway-system
spec:
  host: #{ deployment.host }#
  schema:
    name: AzureOpenAI
    version: "2025-01-01-preview"
  backendSecurityPolicyRef:
    name: azure-openai-#{ deployment.name }#-auth
#% endfor %#
#% endif %#
```

#### 3.2 AI Gateway and Route Configuration

**gateway.yaml.j2**:
```yaml
#% if ai_gateway_enabled %#
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: envoy-ai-gateway
  namespace: envoy-ai-gateway-system
spec:
  gatewayClassName: envoy
  infrastructure:
    annotations:
      lbipam.cilium.io/ips: "#{ ai_gateway_addr }#"
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same
    - name: https
      protocol: HTTPS
      port: 443
      allowedRoutes:
        namespaces:
          from: Same
      tls:
        certificateRefs:
#% for domain in cloudflare_domains %#
          - kind: Secret
            name: #{ domain | replace('.', '-') }#-production-tls
            namespace: network
#% endfor %#
#% endif %#
```

**route.yaml.j2**:
```yaml
#% if ai_gateway_enabled %#
---
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: AIGatewayRoute
metadata:
  name: ai-routes
  namespace: envoy-ai-gateway-system
spec:
  parentRefs:
    - name: envoy-ai-gateway
      kind: Gateway
      group: gateway.networking.k8s.io
  rules:
#% for deployment in ai_gateway_azure_deployments %#
#% for model in deployment.models %#
    - matches:
        - headers:
            - type: Exact
              name: x-ai-eg-model
              value: #{ model }#
      backendRefs:
        - name: azure-openai-#{ deployment.name }#
#% endfor %#
#% endfor %#
#% endif %#
```

### Phase 4: Required Features (Redis & MCP)

#### 4.1 Redis Rate Limiting

Create `templates/config/kubernetes/apps/ai-gateway/redis/`:

**deployment.yaml.j2**:
```yaml
#% if ai_gateway_enabled and ai_gateway_ratelimit_enabled %#
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: envoy-ai-gateway-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          ports:
            - containerPort: 6379
          resources:
            requests:
              memory: "64Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
          livenessProbe:
            tcpSocket:
              port: 6379
            initialDelaySeconds: 10
            periodSeconds: 5
          readinessProbe:
            tcpSocket:
              port: 6379
            initialDelaySeconds: 5
            periodSeconds: 3
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: envoy-ai-gateway-system
spec:
  selector:
    app: redis
  ports:
    - port: 6379
      targetPort: 6379
#% endif %#
```

**ratelimit-policy.yaml.j2**:
```yaml
#% if ai_gateway_enabled and ai_gateway_ratelimit_enabled %#
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: BackendTrafficPolicy
metadata:
  name: ai-gateway-ratelimit
  namespace: envoy-ai-gateway-system
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: ai-gateway-route
  rateLimit:
    type: Global
    global:
      rules:
        - clientSelectors:
            - headers:
                - name: x-user-id
                  type: Distinct
          limit:
            requests: #{ ai_gateway_ratelimit_default_limit }#
            unit: Hour
          cost:
            request:
              from: Number
              number: 0
            response:
              from: Metadata
              metadata:
                namespace: "io.envoy.ai_gateway"
                key: "llmRequestCosts.totalTokens"
#% endif %#
```

#### 4.2 MCP Gateway

Create `templates/config/kubernetes/apps/ai-gateway/mcp/`:

**backend.yaml.j2**:
```yaml
#% if ai_gateway_enabled and ai_gateway_mcp_enabled and ai_gateway_mcp_servers %#
#% for server in ai_gateway_mcp_servers %#
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: Backend
metadata:
  name: mcp-#{ server.name }#
  namespace: envoy-ai-gateway-system
spec:
  endpoints:
    - fqdn:
        hostname: #{ server.host }#
        port: 443
#% endfor %#
#% endif %#
```

**secret.sops.yaml.j2**:
```yaml
#% if ai_gateway_enabled and ai_gateway_mcp_enabled and ai_gateway_mcp_servers %#
#% for server in ai_gateway_mcp_servers %#
#% if server.api_key is defined %#
---
apiVersion: v1
kind: Secret
metadata:
  name: mcp-#{ server.name }#-token
  namespace: envoy-ai-gateway-system
type: Opaque
stringData:
  apiKey: #{ server.api_key }#
#% endif %#
#% endfor %#
#% endif %#
```

**mcproute.yaml.j2**:
```yaml
#% if ai_gateway_enabled and ai_gateway_mcp_enabled and ai_gateway_mcp_servers %#
---
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: MCPRoute
metadata:
  name: mcp-gateway
  namespace: envoy-ai-gateway-system
spec:
  parentRefs:
    - name: envoy-ai-gateway
      kind: Gateway
      group: gateway.networking.k8s.io
  path: "/mcp"
  backendRefs:
#% for server in ai_gateway_mcp_servers %#
    - name: mcp-#{ server.name }#
      kind: Backend
      group: gateway.envoyproxy.io
      path: "#{ server.path | default('/mcp') }#"
#% if server.tool_filter is defined %#
      toolSelector:
        includeRegex:
#% for pattern in server.tool_filter %#
          - #{ pattern }#
#% endfor %#
#% endif %#
#% if server.api_key is defined %#
      securityPolicy:
        apiKey:
          secretRef:
            name: mcp-#{ server.name }#-token
#% endif %#
#% endfor %#
#% endif %#
```

### Phase 5: HTTPRoute Integration

#### 5.1 AI Gateway HTTPRoute (aiops.<domain>)

Create `templates/config/kubernetes/apps/ai-gateway/routes/httproute.yaml.j2`:

```yaml
#% if ai_gateway_enabled %#
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ai-gateway-route
  namespace: envoy-ai-gateway-system
  annotations:
    external-dns.alpha.kubernetes.io/controller: none
spec:
  parentRefs:
    - name: envoy-internal
      namespace: network
      sectionName: https
  hostnames:
    - aiops.${SECRET_DOMAIN}
  rules:
    # LLM API endpoints
    - matches:
        - path:
            type: PathPrefix
            value: /v1/
      backendRefs:
        - name: envoy-ai-gateway
          namespace: envoy-ai-gateway-system
          port: 80
#% if ai_gateway_mcp_enabled %#
    # MCP endpoint
    - matches:
        - path:
            type: PathPrefix
            value: /mcp
      backendRefs:
        - name: envoy-ai-gateway
          namespace: envoy-ai-gateway-system
          port: 80
#% endif %#
#% endif %#
```

#### 5.2 External Access (Optional - via Cloudflare Tunnel)

For external access, add to external gateway:

```yaml
#% if ai_gateway_enabled and ai_gateway_external_enabled | default(false) %#
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ai-gateway-external
  namespace: envoy-ai-gateway-system
  annotations:
    external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
spec:
  parentRefs:
    - name: envoy-external
      namespace: network
      sectionName: https
  hostnames:
    - aiops.${SECRET_DOMAIN}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /v1/
      backendRefs:
        - name: envoy-ai-gateway
          namespace: envoy-ai-gateway-system
          port: 80
#% endif %#
```

## File Structure

```
templates/config/kubernetes/apps/ai-gateway/
├── namespace.yaml.j2
├── crds/
│   ├── ks.yaml.j2
│   └── app/
│       ├── kustomization.yaml.j2
│       ├── helmrelease.yaml.j2
│       └── ocirepository.yaml.j2
├── controller/
│   ├── ks.yaml.j2
│   └── app/
│       ├── kustomization.yaml.j2
│       ├── helmrelease.yaml.j2
│       └── ocirepository.yaml.j2
├── backends/
│   └── azure-openai/
│       ├── ks.yaml.j2
│       └── app/
│           ├── kustomization.yaml.j2
│           ├── backend.yaml.j2
│           └── secret.sops.yaml.j2
├── routes/
│   ├── ks.yaml.j2
│   └── app/
│       ├── kustomization.yaml.j2
│       ├── gateway.yaml.j2
│       ├── route.yaml.j2
│       └── httproute.yaml.j2
├── redis/
│   ├── ks.yaml.j2
│   └── app/
│       ├── kustomization.yaml.j2
│       ├── deployment.yaml.j2
│       └── ratelimit-policy.yaml.j2
└── mcp/
    ├── ks.yaml.j2
    └── app/
        ├── kustomization.yaml.j2
        ├── backend.yaml.j2
        ├── secret.sops.yaml.j2
        └── mcproute.yaml.j2
```

## Flux Kustomization Dependencies

```
flux-system
    ↓
envoy-gateway (network namespace)
    ↓
ai-gateway-crds (envoy-ai-gateway-system)
    ↓
ai-gateway-controller (envoy-ai-gateway-system)
    ↓
ai-gateway-redis (envoy-ai-gateway-system)
    ↓
├── ai-gateway-backends-azure (envoy-ai-gateway-system)
├── ai-gateway-mcp (if mcp enabled)
└── ai-gateway-routes
```

## Configuration Variables Summary

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ai_gateway_enabled` | bool | false | Enable AI Gateway |
| `ai_gateway_version` | string | "v0.4.0" | Chart version |
| `ai_gateway_namespace` | string | "envoy-ai-gateway-system" | Namespace |
| `ai_gateway_addr` | string | (cluster_gateway_addr) | LoadBalancer IP |
| `ai_gateway_azure_deployments` | array | [] | Azure OpenAI deployments |
| `ai_gateway_azure_deployments[].name` | string | - | Deployment identifier |
| `ai_gateway_azure_deployments[].host` | string | - | Azure OpenAI endpoint |
| `ai_gateway_azure_deployments[].api_key` | string | - | API key (SOPS encrypted) |
| `ai_gateway_azure_deployments[].models` | array | - | Models served by deployment |
| `ai_gateway_mcp_enabled` | bool | false | Enable MCP gateway |
| `ai_gateway_mcp_servers` | array | [] | MCP server configurations |
| `ai_gateway_ratelimit_enabled` | bool | false | Enable rate limiting |
| `ai_gateway_ratelimit_default_limit` | int | 100000 | Tokens per hour per user |

## Example Configuration

```yaml
# cluster.yaml
ai_gateway_enabled: true
ai_gateway_addr: "192.168.1.150"

ai_gateway_azure_deployments:
  - name: "eastus-primary"
    host: "mycompany-eastus.openai.azure.com"
    api_key: "abc123..."
    models:
      - "gpt-4"
      - "gpt-4o"
      - "gpt-4o-mini"
  - name: "westus-embedding"
    host: "mycompany-westus.openai.azure.com"
    api_key: "def456..."
    models:
      - "text-embedding-ada-002"
      - "text-embedding-3-large"
  - name: "swedencentral-gpt35"
    host: "mycompany-sweden.openai.azure.com"
    api_key: "ghi789..."
    models:
      - "gpt-35-turbo"
      - "gpt-35-turbo-16k"

ai_gateway_ratelimit_enabled: true
ai_gateway_ratelimit_default_limit: 100000

ai_gateway_mcp_enabled: true
ai_gateway_mcp_servers:
  - name: "github"
    host: "api.githubcopilot.com"
    path: "/mcp/readonly"
    api_key: "ghp_xxxxx"
    tool_filter:
      - ".*issues?.*"
      - ".*pull_requests?.*"
  - name: "context7"
    host: "mcp.context7.io"
    path: "/mcp"
```

## Testing Strategy

### Phase 1 Verification
```bash
# Check CRDs installed
kubectl get crds | grep aigateway

# Check controller running
kubectl get pods -n envoy-ai-gateway-system

# Verify no impact on existing gateways
kubectl get gateway -A
```

### Phase 2 Verification
```bash
# Test buffer limits applied
kubectl get backendtrafficpolicy -n network -o yaml | grep bufferLimit

# Verify Envoy Gateway config
kubectl get envoyproxy -n network -o yaml
```

### Phase 3 Verification (Azure OpenAI)
```bash
# Test Azure OpenAI backend
curl -X POST "https://aiops.$DOMAIN/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "x-ai-eg-model: gpt-4" \
  -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Phase 4 Verification (Redis & MCP)
```bash
# Check Redis is running
kubectl get pods -n envoy-ai-gateway-system -l app=redis

# Test MCP endpoint
curl "https://aiops.$DOMAIN/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "method": "tools/list", "id": 1}'
```

### Phase 5 Verification (HTTPRoute)
```bash
# Test internal access
curl -k "https://aiops.$DOMAIN/v1/models"

# Verify DNS resolution
dig @$CLUSTER_DNS_GATEWAY_ADDR aiops.$DOMAIN
```

## Rollback Procedures

### Phase 1 Rollback
```bash
# Remove AI Gateway components
kubectl delete ns envoy-ai-gateway-system

# Remove CRDs
kubectl delete crds aigatewayroutes.aigateway.envoyproxy.io
kubectl delete crds aiservicebackends.aigateway.envoyproxy.io
kubectl delete crds backendsecuritypolicies.aigateway.envoyproxy.io
kubectl delete crds mcproutes.aigateway.envoyproxy.io
```

### Phase 2 Rollback
```bash
# Revert buffer limits in template
# Run task configure

# Force reconcile
flux reconcile ks envoy-gateway --with-source
```

## Security Considerations

1. **API Key Protection**: All Azure OpenAI API keys stored in SOPS-encrypted secrets
2. **Network Isolation**: AI Gateway in dedicated namespace
3. **RBAC**: Minimal permissions for AI Gateway controller
4. **Rate Limiting**: Token-based limits prevent cost overruns
5. **TLS**: All external traffic via HTTPS through `aiops.<domain>`
6. **MCP Tool Filtering**: Regex patterns limit exposed tools per server

## Azure OpenAI Specific Notes

### Authentication Method
Azure OpenAI uses API Key authentication (not Entra ID OIDC in this implementation):
- Simpler setup than OAuth client credentials flow
- API keys stored in Kubernetes Secrets (SOPS encrypted)
- Each deployment can have its own API key

### Model Routing
- Requests are routed based on `x-ai-eg-model` header
- Each Azure deployment can serve multiple models
- Model names must match Azure deployment names in your Azure OpenAI resource

### API Version
Using `2025-01-01-preview` schema version for latest features.

## Critical v0.4.0 Fixes

> **Status**: These fixes have been validated in production deployment (December 2025).

The following critical corrections were discovered during actual v0.4.0 deployment and must be applied:

### 1. AIGatewayRoute backendRefs - DO NOT Specify kind/group

**Problem**: When `kind` and `group` are explicitly specified in AIGatewayRoute backendRefs, the controller only accepts `InferencePool` (for self-hosted models). For managed services like Azure OpenAI using `AIServiceBackend`, these fields must be **omitted**.

**Error Message**:
```
only InferencePool from inference.networking.k8s.io group is supported
```

**Wrong** (causes validation failure):
```yaml
backendRefs:
  - name: azure-primary
    kind: AIServiceBackend
    group: aigateway.envoyproxy.io
```

**Correct** (works with AIServiceBackend):
```yaml
backendRefs:
  - name: azure-primary
  # Do NOT specify kind or group - they default correctly to AIServiceBackend
```

### 2. BackendSecurityPolicy - Use AzureAPIKey Type for Azure

**Problem**: Azure OpenAI requires the API key in the `api-key` header, not the `Authorization` header.

- `type: APIKey` → Injects into `Authorization: Bearer <key>` header (wrong for Azure)
- `type: AzureAPIKey` → Injects into `api-key: <key>` header (correct for Azure)

**Wrong**:
```yaml
spec:
  type: APIKey
  apiKey:
    secretRef:
      name: azure-secret
```

**Correct**:
```yaml
spec:
  type: AzureAPIKey
  azureAPIKey:
    secretRef:
      name: azure-secret
      namespace: envoy-ai-gateway-system
```

> **Note**: For non-Azure schemas (Cohere, Anthropic via Azure AI), use `type: APIKey` as they expect the standard Authorization header.

### 3. BackendTLSPolicy Required for TLS Backends

**Problem**: Without BackendTLSPolicy, TLS validation fails for outbound connections to Azure/MCP endpoints.

**Required for each Backend**:
```yaml
apiVersion: gateway.networking.k8s.io/v1alpha3
kind: BackendTLSPolicy
metadata:
  name: azure-primary-tls
spec:
  targetRefs:
    - group: gateway.envoyproxy.io
      kind: Backend
      name: azure-primary
  validation:
    wellKnownCACertificates: System
    hostname: my-resource.openai.azure.com
```

### 4. AIServiceBackend Structure Change

**v0.4.0 Structure** (backendRef references separate Backend resource):
```yaml
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: AIServiceBackend
metadata:
  name: azure-primary
spec:
  schema:
    name: AzureOpenAI
    version: "2025-01-01-preview"
  backendRef:
    name: azure-primary
    kind: Backend
    group: gateway.envoyproxy.io
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: Backend
metadata:
  name: azure-primary
spec:
  endpoints:
    - fqdn:
        hostname: my-resource.openai.azure.com
        port: 443
```

### 5. llmRequestCosts Required for Token-Based Rate Limiting

**Problem**: Rate limiting by token consumption requires explicit `llmRequestCosts` configuration in AIGatewayRoute.

**Required in AIGatewayRoute**:
```yaml
spec:
  llmRequestCosts:
    - metadataKey: llm_input_token
      type: InputToken
    - metadataKey: llm_output_token
      type: OutputToken
    - metadataKey: llm_total_token
      type: TotalToken
```

**BackendTrafficPolicy must reference the metadata key**:
```yaml
cost:
  response:
    from: Metadata
    metadata:
      namespace: "io.envoy.ai_gateway"
      key: "llm_total_token"  # Must match llmRequestCosts metadataKey
```

### 6. HTTPRoute Service Name

**Problem**: The service created by Envoy Gateway for the AI Gateway matches the Gateway name, not a custom pattern.

**Gateway name**: `ai-gateway`
**Service created**: `ai-gateway` (in same namespace)

**Correct HTTPRoute backendRef**:
```yaml
backendRefs:
  - name: ai-gateway  # Matches Gateway metadata.name
    namespace: envoy-ai-gateway-system
    kind: Service
    port: 80
```

### 7. Envoy Gateway Rate Limit Backend Configuration

**Problem**: Token-based rate limiting requires Redis configuration in the base Envoy Gateway HelmRelease.

**Add to Envoy Gateway values**:
```yaml
config:
  envoyGateway:
    provider:
      type: Kubernetes
      kubernetes:
        rateLimitDeployment:
          patch:
            type: StrategicMerge
            value:
              spec:
                template:
                  spec:
                    containers:
                      - name: envoy-ratelimit
                        imagePullPolicy: IfNotPresent
    rateLimit:
      backend:
        type: Redis
        redis:
          url: redis.envoy-ai-gateway-system.svc.cluster.local:6379
```

---

## Architecture Clarification

**Q: Does Envoy AI Gateway duplicate Envoy Gateway?**

**A: No.** Envoy AI Gateway is an **extension** that requires Envoy Gateway as a base:

- **Envoy Gateway**: Base component that manages Gateway resources, creates Envoy proxy deployments
- **Envoy AI Gateway**: Extension controller that adds AI-specific CRDs (AIGatewayRoute, AIServiceBackend, etc.)

They are **complementary**, not redundant. The AI Gateway controller watches its custom resources and configures the Envoy proxies created by Envoy Gateway.

---

## Next Steps

1. Review and approve implementation plan
2. Create feature branch
3. Implement Phase 1 (CRDs and Controller)
4. Test on development cluster
5. Proceed with subsequent phases
6. Update CLAUDE.md and README.md documentation
7. Configure split DNS for `aiops.<domain>`
