# Envoy AI Gateway Architecture & Security Research

> Sources:
> - https://aigateway.envoyproxy.io/docs/capabilities/security/upstream-auth
> - https://aigateway.envoyproxy.io/docs/concepts/architecture/system-architecture
> - https://aigateway.envoyproxy.io/docs/concepts/architecture/control-plane
> - https://aigateway.envoyproxy.io/docs/concepts/architecture/data-plane
> - https://aigateway.envoyproxy.io/docs/concepts/resources
> Reviewed: December 2025

## System Architecture Overview

Envoy AI Gateway uses a modern cloud-native architecture with distinct control and data planes.

```
┌─────────────────────────────────────────────────────────────┐
│                     CONTROL PLANE                            │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌──────────────────────────┐       │
│  │  Kubernetes     │    │   AI Gateway Controller   │       │
│  │  API Server     │───▶│  - AI-specific CRDs       │       │
│  └─────────────────┘    │  - ExtProc management     │       │
│                         │  - Credential rotation     │       │
│                         └───────────┬────────────────┘       │
│                                     │                        │
│                         ┌───────────▼────────────────┐       │
│                         │ Envoy Gateway Controller   │       │
│                         │  - xDS configuration       │       │
│                         │  - Gateway API translation │       │
│                         └───────────┬────────────────┘       │
└─────────────────────────────────────┼───────────────────────┘
                                      │ xDS
┌─────────────────────────────────────▼───────────────────────┐
│                      DATA PLANE                              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌──────────────────────────┐       │
│  │   Envoy Proxy   │◀──▶│   External Processor     │       │
│  │  - Routing      │    │   (ExtProc Sidecar)      │       │
│  │  - Load balance │    │   - Schema transform     │       │
│  │  - TLS          │    │   - Auth injection       │       │
│  └────────┬────────┘    │   - Token extraction     │       │
│           │             └──────────────────────────┘       │
│           │                                                 │
│  ┌────────▼────────┐                                       │
│  │ Rate Limit Svc  │                                       │
│  │ - Token-based   │                                       │
│  └─────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘
```

## Control Plane Components

### AI Gateway Controller

**Responsibilities**:
- Manage AI-specific Custom Resources
- Create/update ExtProc Secrets with processing rules
- Inject ExtProc sidecar via Kubernetes Admission Webhooks
- Handle credential rotation
- Generate HTTPRoute and HTTPRouteFilter resources

**Extension Server Integration**:
- Implements Envoy Gateway Extension Server protocol
- Fine-tunes xDS configuration before application
- Addresses Gateway API limitations (upstream filters, backendRef priority)

### Envoy Gateway Controller

**Responsibilities**:
- Core proxy management
- Service discovery
- Load balancing
- TLS termination
- Gateway API translation

**Relationship**: AI Gateway Controller works alongside (not replacing) Envoy Gateway Controller.

## Data Plane Components

### External Processor (ExtProc)

The ExtProc is the core AI-specific processing component, operating in two phases:

#### Router-Level Processing
- Model selection and validation
- Provider-specific authentication
- API format support (OpenAI, AWS Bedrock, etc.)

#### Upstream-Level Processing
- Request transformation for provider compatibility
- Upstream authorization and API key injection
- Response normalization

### Request/Response Flow

**Inbound**:
1. Route determination (path, headers, model extraction)
2. Request body/format adaptation
3. Authentication token management
4. Rate limit validation

**Outbound**:
1. Response transformation for client
2. Token usage extraction
3. Dynamic metadata storage
4. Rate limit enforcement

### Sidecar Architecture

- ExtProc injected as sidecar via Admission Webhooks
- Unix Domain Socket communication with Envoy Proxy
- Local, low-latency processing

## Custom Resource Definitions (CRDs)

### Primary CRDs

| CRD | API Group | Purpose |
|-----|-----------|---------|
| `AIGatewayRoute` | `aigateway.envoyproxy.io/v1alpha1` | Routing rules, API schema, LLM cost tracking |
| `AIServiceBackend` | `aigateway.envoyproxy.io/v1alpha1` | Backend definition, output schema |
| `BackendSecurityPolicy` | `aigateway.envoyproxy.io/v1alpha1` | Authentication configuration |

### Additional CRDs (MCP, Inference)

| CRD | Purpose |
|-----|---------|
| `MCPRoute` | MCP server routing and tool filtering |
| `InferencePool` | Self-hosted model pool (via Gateway API Inference Extension) |

### Resource Relationships

```
AIGatewayRoute
     │
     ├──▶ AIServiceBackend (1:N)
     │         │
     │         └──▶ BackendSecurityPolicy (0:1)
     │
     └──▶ InferencePool (1:N, alternative to AIServiceBackend)
```

## Upstream Authentication

### Authentication Methods

| Provider | Method | Credential Type |
|----------|--------|-----------------|
| OpenAI | API Key | Long-lived, manual rotation |
| AWS Bedrock | OIDC/STS | Short-lived, automatic |
| Azure OpenAI | Entra ID | Short-lived, automatic |
| GCP Vertex AI | Workload Federation | Short-lived, automatic |

### Two-Layer Security Model

```
Client ─────▶ Gateway ─────▶ LLM Provider
        (Layer 1)      (Layer 2)

Layer 1: Client authentication (OAuth, API Key)
Layer 2: Upstream authentication (provider-specific)
```

### API Key Authentication Pattern

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: openai-api-key
  namespace: envoy-ai-gateway-system
type: Opaque
stringData:
  apiKey: sk-...
---
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: BackendSecurityPolicy
metadata:
  name: openai-auth
spec:
  type: APIKey
  apiKey:
    secretRef:
      name: openai-api-key
      key: apiKey
```

### Cloud Provider Authentication

**AWS Bedrock (OIDC)**:
- Uses AWS STS for temporary credentials
- Pod Identity or IRSA recommended

**Azure OpenAI (Entra ID)**:
- OAuth 2.0 client credentials flow
- Requires tenant ID, client ID, client secret

**GCP Vertex AI (Workload Federation)**:
- Service account or Workload Identity
- No static credentials needed

## Security Considerations

### Credential Management
1. Store in Kubernetes Secrets
2. Never commit to version control
3. Implement rotation policies
4. Use SOPS for GitOps encryption

### Least Privilege
- Minimal RBAC permissions
- Provider-specific IAM roles
- Tool filtering for MCP

### Monitoring
- Rate limiting for cost control
- Token usage tracking
- Audit logging

## Project Integration Notes

### Namespace Strategy
AI Gateway components deploy to `envoy-ai-gateway-system`:
- AI Gateway Controller
- CRDs
- ExtProc configuration

### Existing Envoy Gateway
Our project has Envoy Gateway in `network` namespace. Options:
1. Keep separate (recommended for isolation)
2. Co-locate (requires careful configuration)

### Secret Management
Use SOPS encryption for:
- API keys
- OAuth client secrets
- Service account credentials

### Controller Deployment
Single deployment per cluster - coordinates with existing Envoy Gateway controller.
