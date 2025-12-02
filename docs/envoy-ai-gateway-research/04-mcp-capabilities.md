# Envoy AI Gateway MCP Capabilities Research

> Source: https://aigateway.envoyproxy.io/docs/capabilities/mcp/
> Reviewed: December 2025

## MCP Gateway Architecture

The MCP Gateway is a lightweight proxy within the Envoy AI Gateway sidecar, leveraging Envoy's networking stack for connection handling.

### Key Components

| Component | Function |
|-----------|----------|
| **Session Management** | Encodes multiple backend session IDs into unified sessions |
| **Notification Handling** | Merges long-lived SSE streams into single client stream |
| **Request Routing** | Automatic backend prefixing for tool names |
| **Reconnection** | SSE reconnection via `Last-Event-ID` |

### Protocol Support
- MCP Streamable HTTP transport (June 2025 spec)
- Stateful sessions
- Multi-part JSON-RPC messaging
- Persistent HTTP connections

## MCPRoute CRD Specification

### Full Example

```yaml
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: MCPRoute
metadata:
  name: mcp-route
  namespace: default
spec:
  parentRefs:
    - name: envoy-ai-gateway
      kind: Gateway
      group: gateway.networking.k8s.io
  path: "/mcp"
  backendRefs:
    - name: github
      kind: Backend
      group: gateway.envoyproxy.io
      path: "/mcp/readonly"
      toolSelector:
        includeRegex:
          - .*issues?.*
          - .*pull_requests?.*
      securityPolicy:
        apiKey:
          secretRef:
            name: github-token
    - name: context7
      kind: Backend
      group: gateway.envoyproxy.io
      path: "/mcp"
      # No toolSelector = all tools exposed
  securityPolicy:
    oauth:
      issuer: "https://keycloak.example.com/realms/master"
      audiences:
        - "https://api.example.com/mcp"
      protectedResourceMetadata:
        resource: "https://api.example.com/mcp"
        scopesSupported:
          - "profile"
          - "email"
```

### Spec Fields

| Field | Type | Description |
|-------|------|-------------|
| `parentRefs` | []ParentRef | Gateway references |
| `path` | string | MCP endpoint path (e.g., `/mcp`) |
| `backendRefs` | []BackendRef | MCP server backends |
| `securityPolicy` | SecurityPolicy | Client authentication (OAuth) |

### BackendRef Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Backend resource name |
| `kind` | string | `Backend` |
| `group` | string | `gateway.envoyproxy.io` |
| `path` | string | Backend MCP endpoint path |
| `toolSelector` | ToolSelector | Tool filtering config |
| `securityPolicy` | SecurityPolicy | Upstream authentication |

## Tool Filtering

### Exact Match
```yaml
toolSelector:
  include:
    - issue_read
    - list_issues
```

### Regex Match
```yaml
toolSelector:
  includeRegex:
    - .*issues?.*
    - .*pull_requests?.*
```

**Note**: `include` and `includeRegex` are mutually exclusive.

**Default**: All tools exposed if `toolSelector` omitted.

## Server Multiplexing

Multiple backends aggregate into unified interface. Tool names receive automatic prefixes:

```
github__issue_read
github__list_issues
context7__resolve-library-id
context7__get-library-docs
```

### Configuration
Simply add multiple `backendRefs` to MCPRoute - no additional configuration needed.

## OAuth Authentication (Client-Facing)

```yaml
securityPolicy:
  oauth:
    issuer: "https://keycloak.example.com/realms/master"
    audiences:
      - "https://api.example.com/mcp"
    protectedResourceMetadata:
      resource: "https://api.example.com/mcp"
      scopesSupported:
        - "profile"
        - "email"
```

Implements authorization code flow with PKCE per MCP specifications.

## Upstream Authentication (Backend-Facing)

### API Key

```yaml
securityPolicy:
  apiKey:
    secretRef:
      name: github-token
```

### Secret Format

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: github-token
  namespace: default
type: Opaque
stringData:
  apiKey: ghp_your_token_here
```

## Backend Resource Definition

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: Backend
metadata:
  name: github
  namespace: default
spec:
  endpoints:
    - fqdn:
        hostname: api.githubcopilot.com
        port: 443
```

## Observability

- OpenTelemetry tracing
- Prometheus metrics
- Same observability stack as LLM traffic

## MCP Spec Coverage (June 2025)

| Feature | Supported |
|---------|-----------|
| Tool calls | ✅ |
| Notifications | ✅ |
| Prompts | ✅ |
| Resources | ✅ |
| Bidirectional requests | ✅ |
| SSE reconnection | ✅ |
| Session management | ✅ |

## Project Integration Considerations

### CRDs Required
- `MCPRoute` - MCP routing configuration
- `Backend` - MCP server endpoints (Envoy Gateway CRD)

### Template Variables
```yaml
# cluster.yaml
ai_gateway_mcp_enabled: false
ai_gateway_mcp_servers:
  github:
    enabled: true
    path: "/mcp/readonly"
  context7:
    enabled: true
```

### Security
- Use SOPS for API key secrets
- Consider OAuth for production client authentication
- Tool filtering for least-privilege access

### Observability Integration
MCP metrics integrate with existing Prometheus/Grafana stack.
