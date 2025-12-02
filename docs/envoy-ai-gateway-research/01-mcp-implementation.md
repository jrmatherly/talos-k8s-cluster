# Envoy AI Gateway MCP Implementation Research

> Source: https://aigateway.envoyproxy.io/blog/mcp-implementation
> Reviewed: December 2025

## Overview

Model Context Protocol (MCP) is an industry standard enabling AI agents to securely connect to external tools and data sources. The Envoy AI Gateway provides first-class MCP support as of v0.4.0, addressing the shift "from monolithic models to agentic architectures."

## Core Purpose

MCP allows agents to interact with external services through a standardized protocol:
- Secure tool invocation
- Data source integration
- Enterprise stack connectivity
- Policy-driven access control

## Architecture

### Components

| Component | Description |
|-----------|-------------|
| **MCP Proxy** | Lightweight Go server handling session management and stream multiplexing |
| **Envoy Integration** | Leverages Envoy's networking for connection management, load balancing, circuit breaking, rate-limiting |
| **Stateless Design** | No additional components beyond existing AI Gateway architecture |

### Protocol Support
- Full June 2025 MCP specification compliance
- Streamable HTTP transport with stateful session handling
- SSE support with reconnection logic (Last-Event-ID)

## Configuration Examples

### Standalone Mode (mcp-servers.json)

```json
{
  "mcpServers": {
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/readonly",
      "headers": {
        "Authorization": "Bearer ${GITHUB_ACCESS_TOKEN}"
      },
      "tools": ["issue_read", "list_issues"]
    }
  }
}
```

Launch: `aigw run --mcp-config mcp-servers.json`
Endpoint: `http://localhost:1975/mcp`

### Kubernetes MCPRoute Resource

```yaml
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: MCPRoute
metadata:
  name: mcp-route
  namespace: default
spec:
  parentRefs:
    - name: aigw-run
      kind: Gateway
      group: gateway.networking.k8s.io
  backendRefs:
    - name: github
      kind: Backend
      group: gateway.envoyproxy.io
      path: "/mcp/readonly"
      toolSelector:
        includeRegex:
          - .*pull_requests?.*
          - .*issues?.*
      securityPolicy:
        apiKey:
          secretRef:
            name: github-access-token
  securityPolicy:
    oauth:
      issuer: "https://auth-server.example.com"
      protectedResourceMetadata:
        resource: "http://localhost:1975/mcp"
        scopesSupported:
          - "profile"
          - "email"
```

## Key Features

| Feature | Details |
|---------|---------|
| **Streamable HTTP Transport** | Full June 2025 MCP spec with stateful sessions |
| **OAuth Authorization** | Native enforcement, backwards compatible |
| **Tool Routing & Filtering** | Route to backends, filter by regex |
| **Server Multiplexing** | Aggregate tools from multiple servers |
| **Upstream Authentication** | Credential injection for external MCP servers |
| **Full Spec Coverage** | Tools, notifications, prompts, resources, bi-directional |
| **Session Management** | Reconnection logic with Last-Event-ID for SSE |

## OAuth Authentication

```yaml
securityPolicy:
  oauth:
    issuer: "https://auth-server.example.com"
    protectedResourceMetadata:
      resource: "http://localhost:1975/mcp"
      scopesSupported:
        - "profile"
        - "email"
```

Supports both June 2025 and March 2026 authorization specifications.

## Tool Routing & Filtering

### Via JSON config
```json
"tools": ["issue_read", "list_issues"]
```

### Via MCPRoute regex
```yaml
toolSelector:
  includeRegex:
    - .*pull_requests?.*
    - .*issues?.*
```

## Server Multiplexing

The gateway dynamically handles multiple MCP servers:
1. Aggregates available tools across backends
2. Applies policy-based filtering using regex patterns
3. Routes tool invocations to correct servers
4. Merges responses for unified agent interface

## Observability

Built-in capabilities via Envoy's networking stack:
- Connection monitoring
- Load balancing visibility
- Circuit breaker status
- Rate-limiting insights
- Full protocol test coverage

## Deployment Modes

| Mode | Use Case |
|------|----------|
| **Standalone** | Local development, testing |
| **Kubernetes** | Production deployments |

Both modes use identical configuration, enabling seamless transition.

## Tested Integrations

- GitHub MCP server
- Context7 provider
- Goose agent framework
- Claude Code

## Project Relevance

For our Talos cluster template:
- MCPRoute is a new CRD to consider
- OAuth integration may require additional infrastructure
- Tool filtering provides security controls
- Server multiplexing enables multi-tool architectures
