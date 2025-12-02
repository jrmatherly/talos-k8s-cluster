# Envoy AI Gateway Provider Connection Research

> Sources:
> - https://aigateway.envoyproxy.io/docs/getting-started/connect-providers/
> - https://aigateway.envoyproxy.io/docs/getting-started/connect-providers/azure-openai
> - https://aigateway.envoyproxy.io/docs/capabilities/llm-integrations/connect-providers
> Reviewed: December 2025

## Supported Providers

| Provider | Schema | Authentication |
|----------|--------|----------------|
| OpenAI | `OpenAI` v1 | API Key |
| AWS Bedrock | `AWSBedrock` | EKS Pod Identity, IRSA, Static credentials |
| Azure OpenAI | `AzureOpenAI` 2025-01-01-preview | Entra ID (OIDC) |
| GCP Vertex AI | `GCPVertexAI` | Service Account, Workload Identity |
| GCP Anthropic (Vertex) | `GCPAnthropic` vertex-2023-10-16 | Service Account, Workload Identity |
| Groq | OpenAI-compatible | API Key |
| Self-hosted (vLLM) | OpenAI-compatible | Custom |

**Note**: Many providers offer OpenAI-compatible APIs, enabling use with OpenAI schema configuration.

## Core Resource Architecture

Three Kubernetes resources required for each provider:

```
┌─────────────────────┐
│   AIGatewayRoute    │ ← Routes requests to backends
├─────────────────────┤
│  AIServiceBackend   │ ← Bridges gateway to provider API
├─────────────────────┤
│BackendSecurityPolicy│ ← Manages authentication
└─────────────────────┘
```

## Authentication by Provider

### OpenAI (API Key)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: openai-credentials
  namespace: envoy-ai-gateway-system
type: Opaque
data:
  apiKey: <base64-encoded-api-key>
---
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: BackendSecurityPolicy
metadata:
  name: openai-auth
spec:
  type: APIKey
  apiKey:
    secretRef:
      name: openai-credentials
      key: apiKey
```

### AWS Bedrock

**Option 1: EKS Pod Identity (Recommended)**
- Automatic credential injection
- No static credentials needed

**Option 2: IRSA**
- Automatically detected by SDK

**Option 3: Static Credentials**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: aws-credentials
type: Opaque
data:
  credentials: <base64-encoded-aws-credentials-file>
```

### Azure OpenAI (Entra ID)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: azure-credentials
type: Opaque
data:
  client-secret: <base64-encoded-client-secret>
---
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: BackendSecurityPolicy
metadata:
  name: azure-auth
spec:
  type: AzureCredentials
  azure:
    tenantID: "<tenant-id>"
    clientID: "<client-id>"
    clientSecretRef:
      name: azure-credentials
      key: client-secret
```

**Note**: API Key authentication not yet supported for Azure.

### GCP Vertex AI

**Option 1: Service Account Key**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gcp-credentials
type: Opaque
data:
  credentials.json: <base64-encoded-service-account-json>
```

**Option 2: Workload Identity Federation**
- OIDC provider integration
- No static credentials

## AIServiceBackend Configuration

### OpenAI Example

```yaml
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: AIServiceBackend
metadata:
  name: openai-backend
spec:
  host: api.openai.com
  schema:
    name: OpenAI
    version: v1
  backendSecurityPolicyRef:
    name: openai-auth
```

### Azure OpenAI Example

```yaml
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: AIServiceBackend
metadata:
  name: azure-openai-backend
spec:
  host: <your-resource>.openai.azure.com
  schema:
    name: AzureOpenAI
    version: "2025-01-01-preview"
  backendSecurityPolicyRef:
    name: azure-auth
```

### AWS Bedrock Example

```yaml
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: AIServiceBackend
metadata:
  name: bedrock-backend
spec:
  host: bedrock-runtime.us-east-1.amazonaws.com
  schema:
    name: AWSBedrock
  backendSecurityPolicyRef:
    name: aws-auth
```

## AIGatewayRoute Configuration

### Basic Routing (Header Match)

```yaml
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: AIGatewayRoute
metadata:
  name: ai-routes
  namespace: default
spec:
  parentRefs:
    - name: envoy-ai-gateway-basic
      kind: Gateway
      group: gateway.networking.k8s.io
  rules:
    - matches:
        - headers:
            - type: Exact
              name: x-ai-eg-model
              value: gpt-4
      backendRefs:
        - name: openai-backend
    - matches:
        - headers:
            - type: Exact
              name: x-ai-eg-model
              value: gpt-4o
      backendRefs:
        - name: azure-openai-backend
```

### Model Metadata

```yaml
spec:
  rules:
    - backendRefs:
        - name: openai-backend
          modelsOwnedBy: "openai"
          modelsCreatedAt: "2024-01-01T00:00:00Z"
```

## Request Data Flow

```
Client Request
     ↓
Route Matching (x-ai-eg-model header)
     ↓
Backend Resolution
     ↓
Authentication (credential injection)
     ↓
Schema Transformation (OpenAI → Provider format)
     ↓
Provider Communication
     ↓
Response Processing
     ↓
Client Response
```

## Security Best Practices

1. **Kubernetes Secrets**: Store all credentials in K8s secrets
2. **Never commit**: API keys must not be in version control
3. **Rotation**: Implement regular credential rotation
4. **Least privilege**: Use minimal permissions required
5. **Monitoring**: Enable usage monitoring and rate limiting
6. **SOPS encryption**: For GitOps, encrypt secrets with SOPS/age

## Error Codes

| Code | Meaning |
|------|---------|
| 401 | Invalid credentials |
| 403 | Insufficient permissions |
| 404 | Model unavailable in region |
| 429 | Rate limit exceeded |

## Project Integration Notes

### For SOPS-encrypted Secrets
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: openai-credentials
  namespace: envoy-ai-gateway-system
type: Opaque
stringData:
  apiKey: ENC[AES256_GCM,data:...,type:str]
sops:
  # SOPS metadata
```

### Provider Selection for Template
Consider making these configurable in `cluster.yaml`:
- `ai_gateway_openai_enabled: true`
- `ai_gateway_azure_enabled: false`
- `ai_gateway_bedrock_enabled: false`
- `ai_gateway_vertex_enabled: false`

### Secret Management Strategy
- Use SOPS for GitOps-managed secrets
- Consider External Secrets Operator for cloud-native secret stores
- Workload Identity preferred over static credentials
