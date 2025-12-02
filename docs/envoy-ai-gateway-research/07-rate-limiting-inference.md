# Envoy AI Gateway Rate Limiting & Inference Pool Research

> Sources:
> - https://aigateway.envoyproxy.io/docs/capabilities/traffic/usage-based-ratelimiting
> - https://raw.githubusercontent.com/envoyproxy/ai-gateway/main/examples/token_ratelimit/envoy-gateway-values-addon.yaml
> - https://raw.githubusercontent.com/envoyproxy/ai-gateway/main/examples/inference-pool/envoy-gateway-values-addon.yaml
> Reviewed: December 2025

## Usage-Based Rate Limiting

### Overview

Token-based rate limiting enables cost control and fair usage enforcement based on actual LLM token consumption rather than simple request counts.

### Token Types

| Type | Description | Use Case |
|------|-------------|----------|
| `InputToken` | Tokens in request | Cost control for input |
| `CachedInputToken` | Cached prompt tokens | Track cache efficiency |
| `OutputToken` | Tokens in response | Cost control for output |
| `TotalToken` | Input + Output | Overall usage limits |
| `CEL` | Custom expression | Complex calculations |

### Architecture

```
Client Request
     ↓
Envoy Proxy → ExtProc (token extraction)
     ↓
Rate Limit Service (Redis) → Decision
     ↓
Allow/Deny Response
```

### Prerequisites

1. **Redis Deployment** - Required for rate limit state storage
2. **Rate Limit Addon** - Envoy Gateway configured with rate limit values
3. **BackendTrafficPolicy** - Defines rate limit rules

### Envoy Gateway Rate Limit Addon

```yaml
# envoy-gateway-values-addon.yaml
config:
  envoyGateway:
    rateLimit:
      backend:
        type: Redis
        redis:
          url: redis.envoy-ai-gateway-system.svc:6379
```

### BackendTrafficPolicy Configuration

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: BackendTrafficPolicy
metadata:
  name: token-ratelimit
  namespace: default
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: ai-routes
  rateLimit:
    type: Global
    global:
      rules:
        - clientSelectors:
            - headers:
                - name: x-user-id
                  type: Distinct
          limit:
            requests: 1000
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
```

### Token Extraction Flow

1. Request processed by AI provider
2. Response contains usage metadata
3. ExtProc extracts token counts
4. Dynamic metadata stored: `io.envoy.ai_gateway.llmRequestCosts`
5. Rate limit service applies cost

### CEL Custom Calculations

```yaml
cost:
  response:
    from: CEL
    cel:
      expression: "metadata['io.envoy.ai_gateway']['llmRequestCosts']['inputTokens'] * 2 + metadata['io.envoy.ai_gateway']['llmRequestCosts']['outputTokens'] * 5"
```

### Rate Limit Metadata Keys

| Key | Description |
|-----|-------------|
| `llmRequestCosts.inputTokens` | Request token count |
| `llmRequestCosts.outputTokens` | Response token count |
| `llmRequestCosts.totalTokens` | Combined count |
| `llmRequestCosts.cachedInputTokens` | Cached tokens (if applicable) |

## Inference Pool Integration

### Purpose

InferencePool enables intelligent routing to self-hosted model endpoints with:
- Dynamic endpoint discovery
- Metrics-based load balancing
- Integration with vLLM, Ollama, and other model servers

### Envoy Gateway Extension Configuration

```yaml
# envoy-gateway-values-addon.yaml for InferencePool
config:
  envoyGateway:
    extensionManager:
      backendResources:
        - group: inference.networking.k8s.io
          kind: InferencePool
          version: v1
```

### Full Installation with Addons

```bash
# Install Envoy Gateway with both addons
helm upgrade -i eg oci://docker.io/envoyproxy/gateway-helm \
  --version v0.0.0-latest \
  --namespace envoy-gateway-system \
  --create-namespace \
  -f https://raw.githubusercontent.com/envoyproxy/ai-gateway/main/manifests/envoy-gateway-values.yaml \
  -f https://raw.githubusercontent.com/envoyproxy/ai-gateway/main/examples/token_ratelimit/envoy-gateway-values-addon.yaml \
  -f https://raw.githubusercontent.com/envoyproxy/ai-gateway/main/examples/inference-pool/envoy-gateway-values-addon.yaml
```

### InferencePool CRD

```yaml
apiVersion: inference.networking.k8s.io/v1
kind: InferencePool
metadata:
  name: vllm-pool
  namespace: default
spec:
  selector:
    app: vllm
  targetPort: 8080
  endpointPickerProvider:
    name: default-epp
```

### Endpoint Picker Provider (EPP)

EPP handles intelligent endpoint selection:
- Monitors model server metrics (KV-cache, queue depth)
- Selects optimal endpoint for each request
- Handles endpoint health and availability

## Redis Deployment for Rate Limiting

### Basic Redis Deployment

```yaml
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
              memory: "128Mi"
              cpu: "250m"
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
```

### Production Considerations

For production:
- Use Redis Sentinel or Redis Cluster for HA
- Enable persistence (RDB/AOF)
- Configure authentication
- Set appropriate memory limits

## Project Integration Notes

### Rate Limiting Integration

Template variables for `cluster.yaml`:
```yaml
ai_gateway_ratelimit_enabled: false
ai_gateway_ratelimit_redis_url: "redis.envoy-ai-gateway-system.svc:6379"
ai_gateway_ratelimit_default_limit: 10000  # tokens per hour
```

### Inference Pool Integration

Template variables:
```yaml
ai_gateway_inference_pool_enabled: false
ai_gateway_self_hosted_models: []
  # - name: llama3
  #   pool_name: vllm-llama3
  #   port: 8080
```

### Helm Values Merging

For Flux HelmRelease, addon values can be merged:
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: envoy-gateway
spec:
  values:
    config:
      envoyGateway:
        rateLimit:
          backend:
            type: Redis
            redis:
              url: redis.envoy-ai-gateway-system.svc:6379
        extensionManager:
          backendResources:
            - group: inference.networking.k8s.io
              kind: InferencePool
              version: v1
```

### Dependencies

Rate limiting requires:
1. Redis deployed before AI Gateway
2. Envoy Gateway configured with rate limit addon
3. BackendTrafficPolicy resources

Inference Pool requires:
1. Gateway API Inference Extension CRDs
2. Envoy Gateway configured with extension manager
3. EPP deployment for intelligent routing
