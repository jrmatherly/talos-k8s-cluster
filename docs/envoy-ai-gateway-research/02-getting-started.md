# Envoy AI Gateway Getting Started Research

> Sources:
> - https://aigateway.envoyproxy.io/docs/getting-started/prerequisites
> - https://aigateway.envoyproxy.io/docs/getting-started/installation
> - https://aigateway.envoyproxy.io/docs/getting-started/basic-usage
> Reviewed: December 2025

## Prerequisites

### Kubernetes Version
- **Minimum**: Kubernetes 1.29+
- **Recommended**: Latest stable version
- **Our Project**: v1.34.2 ✅ Exceeds requirement

### Envoy Gateway Version
- **Minimum**: Envoy Gateway 1.5.0+
- **Recommended**: Latest version
- **Our Project**: v1.6.0 ✅ Exceeds requirement

### Required CLI Tools

| Tool | Purpose | Verification |
|------|---------|--------------|
| kubectl | Cluster management | `kubectl version --client` |
| helm | Package management | `helm version` |
| curl | API testing | `curl --version` |

### Envoy Gateway Installation for AI Gateway

**Important**: AI Gateway requires Envoy Gateway with specific configuration values:

```bash
helm upgrade -i eg oci://docker.io/envoyproxy/gateway-helm \
  --version v0.4.0 \
  --namespace envoy-gateway-system \
  --create-namespace \
  -f https://raw.githubusercontent.com/envoyproxy/ai-gateway/main/manifests/envoy-gateway-values.yaml
```

### Optional Addons
- Rate Limiting addon
- InferencePool addon

Both installed via additional `-f` flags with addon values files.

## Installation

### Step 1: Install CRDs

```bash
helm upgrade -i aieg-crd oci://docker.io/envoyproxy/ai-gateway-crds-helm \
  --version v0.4.0 \
  --namespace envoy-ai-gateway-system \
  --create-namespace
```

### Step 2: Install AI Gateway Controller

```bash
helm upgrade -i aieg oci://docker.io/envoyproxy/ai-gateway-helm \
  --version v0.4.0 \
  --namespace envoy-ai-gateway-system \
  --create-namespace
```

### Namespace
- Default: `envoy-ai-gateway-system`
- `--create-namespace` auto-creates if absent

### Version Pinning (Production)

**Critical**: Replace `v0.0.0-latest` with specific version:
```
--version v0.0.0-${commit-hash}
```

Or use release tags like `v0.4.0`.

### Post-Installation Verification

```bash
# Check pods
kubectl get pods -n envoy-ai-gateway-system

# Wait for controller
kubectl wait --timeout=2m -n envoy-ai-gateway-system \
  deployment/ai-gateway-controller --for=condition=Available
```

### Upgrade from Previous Installation

If only `ai-gateway-helm` was installed (no separate CRD chart):

```bash
helm upgrade -i aieg-crd oci://docker.io/envoyproxy/ai-gateway-crds-helm \
  --version v0.4.0 \
  --namespace envoy-ai-gateway-system \
  --take-ownership
```

### Alternative: Install from Git Repository

If docker.io access issues:
```bash
git clone https://github.com/envoyproxy/ai-gateway.git
helm upgrade -i aieg ./ai-gateway/charts/ai-gateway-helm \
  --namespace envoy-ai-gateway-system \
  --create-namespace
```

## Basic Usage

### Deploy Basic Configuration

```bash
kubectl apply -f https://raw.githubusercontent.com/envoyproxy/ai-gateway/main/examples/basic/basic.yaml
```

### Buffer Limit Configuration

**Critical**: Default 32KB buffer is insufficient for AI responses.

The basic configuration includes ClientTrafficPolicy with 50MB buffer:
```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: ClientTrafficPolicy
metadata:
  name: ai-gateway-buffer
spec:
  connection:
    bufferLimit: 50Mi  # Required for AI responses
```

**Our Project Note**: Current buffer is 8Mi (backend) / 4Mi (client) - needs increase for AI workloads.

### Gateway Access

**Option 1: External IP**
```bash
export GATEWAY_URL=$(kubectl get gateway/envoy-ai-gateway-basic \
  -o jsonpath='{.status.addresses[0].value}')
```

**Option 2: Port Forward**
```bash
export GATEWAY_URL="http://localhost:8080"
kubectl port-forward -n envoy-gateway-system svc/$ENVOY_SERVICE 8080:80
```

### Supported API Endpoints

| Endpoint | Method | Path |
|----------|--------|------|
| Chat Completions | POST | `/v1/chat/completions` |
| Completions (Legacy) | POST | `/v1/completions` |
| Embeddings | POST | `/v1/embeddings` |
| Rerank (Cohere) | POST | `/cohere/v2/rerank` |

### Example: Chat Completions Request

```bash
curl -X POST "$GATEWAY_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [
      {"role": "user", "content": "Hello!"}
    ]
  }'
```

### Response Format (Chat Completions)

```json
{
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "Hello! How can I help you today?"
      }
    }
  ]
}
```

## Project Integration Considerations

### Helm Chart Sources
For Flux GitOps, need OCI repositories:
- CRDs: `oci://docker.io/envoyproxy/ai-gateway-crds-helm`
- Controller: `oci://docker.io/envoyproxy/ai-gateway-helm`

### Namespace Strategy
Options:
1. Dedicated `envoy-ai-gateway-system` (default)
2. Co-locate with existing `network` namespace (requires testing)

### Buffer Limit Update Required
Our current Envoy Gateway needs buffer increase:
- Current: 8Mi backend / 4Mi client
- Required: 50Mi+ for AI responses

### Version Management
- Pin to specific version for production
- Current stable: v0.3.0
- Current release: v0.4.0
