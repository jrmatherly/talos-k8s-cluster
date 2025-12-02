# Envoy AI Gateway Implementation Plan - Addendum

This addendum documents additional changes required across the project that were not captured in the original implementation plan.

> **Implementation Status**: Successfully deployed December 2025. See [Deployment Lessons Learned](#deployment-lessons-learned) for critical fixes discovered during deployment.

## Version Update

**Important**: The latest stable version is **v0.4.0** (released November 8, 2025), not the previously noted version. Update all references accordingly.

---

## 1. GitHub Tests Configuration

### Files to Update

#### `.github/tests/public.yaml`

Add AI Gateway test configuration with full feature set:

```yaml
# Add after proxmox_ccm_token_secret line:

# AI Gateway Integration (optional - full testing)
ai_gateway_enabled: true
ai_gateway_version: "v0.4.0"
ai_gateway_addr: "10.10.10.250"
ai_gateway_azure_deployments:
  - name: "test-primary"
    host: "test-resource.openai.azure.com"
    api_key: "fake-api-key"
    models: ["gpt-4", "gpt-4o"]
  - name: "test-secondary"
    host: "test-resource-2.openai.azure.com"
    api_key: "fake-api-key-2"
    models: ["gpt-35-turbo"]
ai_gateway_ratelimit_enabled: true
ai_gateway_ratelimit_default_limit: 50000
ai_gateway_mcp_enabled: true
ai_gateway_mcp_servers:
  - name: "test-github"
    host: "api.githubcopilot.com"
    path: "/mcp/readonly"
    api_key: "fake-token"
    tool_filter: [".*issues?.*"]
```

#### `.github/tests/private.yaml`

Add minimal AI Gateway test configuration:

```yaml
# Add after proxmox_csi_token_secret line:

# AI Gateway Integration (optional - minimal testing)
ai_gateway_enabled: true
ai_gateway_azure_deployments:
  - name: "test"
    host: "test.openai.azure.com"
    api_key: "fake"
    models: ["gpt-4"]
# ai_gateway_ratelimit_enabled: false  # uses default
# ai_gateway_mcp_enabled: false  # uses default
```

---

## 2. CUE Schema Updates

### File: `.taskfiles/template/resources/cluster.schema.cue`

Add after the Proxmox CCM section (line ~41):

```cue
	// Envoy AI Gateway Integration
	ai_gateway_enabled?: bool
	ai_gateway_version?: string & !=""
	ai_gateway_addr?: net.IPv4 & !=cluster_api_addr & !=cluster_gateway_addr & !=cluster_dns_gateway_addr & !=cloudflare_gateway_addr
	ai_gateway_azure_deployments?: [...{
		name: string & =~"^[a-z0-9-]+$"
		host: string & =~"^.+\\.openai\\.azure\\.com$"
		api_key: string & !=""
		models: [...string] & [_, ...]  // At least one model required
	}]
	ai_gateway_mcp_enabled?: bool
	ai_gateway_mcp_servers?: [...{
		name: string & =~"^[a-z0-9-]+$"
		host: net.FQDN
		path?: string
		api_key?: string & !=""
		tool_filter?: [...string]
	}]
	ai_gateway_ratelimit_enabled?: bool
	ai_gateway_ratelimit_default_limit?: int & >0
```

---

## 3. Sample Configuration Updates

### File: `.taskfiles/template/resources/cluster.sample.yaml`

Add before the closing section (after Proxmox CCM section):

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
#    REF: https://github.com/envoyproxy/ai-gateway/releases
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
#    Each server aggregates into a unified MCP endpoint at /mcp.
#    Tool names are auto-prefixed with server name (e.g., github__list_issues).
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
#    Rate limits are based on actual token consumption, not request count.
#    (OPTIONAL) / (DEFAULT: false)
# ai_gateway_ratelimit_enabled: false

# -- Default token rate limit per hour per user.
#    Applied per distinct x-user-id header value.
#    (OPTIONAL) / (DEFAULT: 100000)
# ai_gateway_ratelimit_default_limit: 100000
```

---

## 4. Plugin.py Data Enrichment

### File: `templates/scripts/plugin.py`

Add to the `data()` method after Proxmox defaults (around line 188):

```python
        # Envoy AI Gateway defaults
        data.setdefault("ai_gateway_enabled", False)
        data.setdefault("ai_gateway_version", "v0.4.0")
        data.setdefault("ai_gateway_namespace", "envoy-ai-gateway-system")
        # Default to cluster_gateway_addr if ai_gateway_addr not specified
        data.setdefault("ai_gateway_addr", data.get("cluster_gateway_addr", ""))
        data.setdefault("ai_gateway_azure_deployments", [])
        data.setdefault("ai_gateway_mcp_enabled", False)
        data.setdefault("ai_gateway_mcp_servers", [])
        data.setdefault("ai_gateway_ratelimit_enabled", False)
        data.setdefault("ai_gateway_ratelimit_default_limit", 100000)
```

---

## 5. Bootstrap Helmfile Updates

### File: `bootstrap/helmfile.d/00-crds.yaml`

The AI Gateway CRDs are deployed via Flux (not helmfile bootstrap), so **no changes required** to this file. The bootstrap process only needs core CRDs for initial cluster operation.

**Rationale**: AI Gateway is an optional feature that deploys after the cluster is bootstrapped and Flux is running.

---

## 6. Scripts Updates

### File: `scripts/bootstrap-apps.sh`

**No changes required**. The bootstrap script handles:
1. Namespaces - AI Gateway namespace created by Flux Kustomization
2. Secrets - AI Gateway secrets created by rendered templates
3. CRDs - AI Gateway CRDs installed by dedicated HelmRelease via Flux

The AI Gateway components are intentionally deployed post-bootstrap via Flux GitOps, not during initial cluster bootstrap.

---

## 7. Documentation Updates

### File: `README.md`

Add to the "✨ Features" section (after cloudflared):

```markdown
- **Included components:** ... [existing list] ... and optionally [envoy-ai-gateway](https://github.com/envoyproxy/ai-gateway) for AI/LLM traffic management.
```

Add new section after "### Storage":

```markdown
### AI Gateway (Optional)

For AI/LLM workload management, this template includes optional [Envoy AI Gateway](https://aigateway.envoyproxy.io/) integration:

- **Multiple Azure OpenAI deployments** with model-based routing
- **MCP (Model Context Protocol)** gateway for agent tool integration
- **Token-based rate limiting** via Redis
- **Unified API endpoint** at `aiops.<domain>`

Enable by setting `ai_gateway_enabled: true` in `cluster.yaml`. See the configuration comments for detailed setup instructions.
```

### File: `CLAUDE.md`

Add new section after "## Proxmox CSI Integration":

```markdown
## Envoy AI Gateway Integration

For AI/LLM traffic management, add to `cluster.yaml`:
- `ai_gateway_enabled` - Enable AI Gateway (default: false)
- `ai_gateway_version` - Chart version (default: "v0.4.0")
- `ai_gateway_addr` - LoadBalancer IP (default: cluster_gateway_addr)
- `ai_gateway_azure_deployments` - Array of Azure OpenAI configurations
- `ai_gateway_mcp_enabled` - Enable MCP gateway (default: false)
- `ai_gateway_mcp_servers` - Array of MCP server configurations
- `ai_gateway_ratelimit_enabled` - Enable Redis rate limiting (default: false)

**API Endpoint**: `aiops.<domain>` routes to AI Gateway.

**Note:** AI Gateway templates are conditionally rendered only when `ai_gateway_enabled` is true.
```

Add to "## Debugging" section:

```bash
# AI Gateway diagnostics (if enabled)
kubectl get pods -n envoy-ai-gateway-system
kubectl get aigatewayroutes -n envoy-ai-gateway-system
kubectl get aiservicebackends -n envoy-ai-gateway-system
kubectl logs -n envoy-ai-gateway-system deploy/ai-gateway-controller
```

---

## 8. Environment Variables

### File: `.mise.toml`

**No changes required**. The AI Gateway does not require additional environment variables beyond the existing `KUBECONFIG`, `SOPS_AGE_KEY_FILE`, and `TALOSCONFIG`.

---

## 9. Taskfile Updates

### File: `Taskfile.yaml`

**No changes required** to main Taskfile. AI Gateway management is handled via:
- `task configure` - Renders AI Gateway templates
- `task reconcile` - Syncs AI Gateway via Flux
- Standard kubectl commands for debugging

Optional future enhancement (not required for initial implementation):

```yaml
# Could add to Taskfile.yaml if desired
  ai-gateway:status:
    desc: Check AI Gateway status
    cmds:
      - kubectl get pods -n envoy-ai-gateway-system
      - kubectl get aigatewayroutes -n envoy-ai-gateway-system
      - kubectl get aiservicebackends -n envoy-ai-gateway-system
    preconditions:
      - test -f {{.KUBECONFIG}}
```

---

## 10. Template Directory Structure

### New Directories to Create

```
templates/config/kubernetes/apps/ai-gateway/
├── ks.yaml.j2                          # Parent Kustomization
├── namespace/
│   ├── ks.yaml.j2
│   └── app/
│       ├── kustomization.yaml.j2
│       └── namespace.yaml.j2
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
├── redis/
│   ├── ks.yaml.j2
│   └── app/
│       ├── kustomization.yaml.j2
│       └── deployment.yaml.j2
├── backends/
│   └── azure-openai/
│       ├── ks.yaml.j2
│       └── app/
│           ├── kustomization.yaml.j2
│           ├── backend.yaml.j2
│           └── secret.sops.yaml.j2
├── mcp/
│   ├── ks.yaml.j2
│   └── app/
│       ├── kustomization.yaml.j2
│       ├── backend.yaml.j2
│       ├── mcproute.yaml.j2
│       └── secret.sops.yaml.j2
└── routes/
    ├── ks.yaml.j2
    └── app/
        ├── kustomization.yaml.j2
        ├── gateway.yaml.j2
        ├── route.yaml.j2
        ├── httproute.yaml.j2
        └── ratelimit-policy.yaml.j2
```

---

## 11. Flux Kustomization Entry Point

### File: `templates/config/kubernetes/flux/cluster/ks.yaml.j2`

Add conditional AI Gateway include:

```yaml
#% if ai_gateway_enabled %#
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: ai-gateway
  namespace: flux-system
spec:
  interval: 1h
  path: ./kubernetes/apps/ai-gateway
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: envoy-gateway
#% endif %#
```

---

## 12. Validation Considerations

### Kubeconform Updates

The kubeconform script (`.taskfiles/template/resources/kubeconform.sh`) may need updated CRD schemas for AI Gateway resources. The script already supports skipping unknown CRDs, but for proper validation:

```bash
# Add to kubeconform.sh if AI Gateway CRD validation is desired
# Download from: https://github.com/envoyproxy/ai-gateway/tree/main/api
```

For initial implementation, AI Gateway resources can be skipped by kubeconform's `--skip` flag.

---

## Summary of Required Changes

| File/Location | Change Type | Priority |
|--------------|-------------|----------|
| `.taskfiles/template/resources/cluster.schema.cue` | Add AI Gateway schema | Required |
| `.taskfiles/template/resources/cluster.sample.yaml` | Add AI Gateway examples | Required |
| `templates/scripts/plugin.py` | Add data defaults | Required |
| `.github/tests/public.yaml` | Add test config | Required |
| `.github/tests/private.yaml` | Add minimal test | Required |
| `README.md` | Add feature docs | Recommended |
| `CLAUDE.md` | Add debug/config docs | Recommended |
| `templates/config/kubernetes/apps/ai-gateway/` | Create templates | Required |
| `templates/config/kubernetes/flux/cluster/ks.yaml.j2` | Add conditional | Required |
| `Taskfile.yaml` | Optional status task | Optional |
| `.mise.toml` | No changes | N/A |
| `bootstrap/helmfile.d/` | No changes | N/A |
| `scripts/` | No changes | N/A |

---

## Implementation Order

1. **Schema & Defaults** (plugin.py, cluster.schema.cue, cluster.sample.yaml)
2. **Test Configurations** (.github/tests/*.yaml)
3. **Template Structure** (templates/config/kubernetes/apps/ai-gateway/)
4. **Flux Entry Point** (ks.yaml.j2 update)
5. **Documentation** (README.md, CLAUDE.md)
6. **Validation** (run `task configure` with test config)

---

## Deployment Lessons Learned

> **Date**: December 2025
> **Version**: Envoy AI Gateway v0.4.0

The following critical issues were discovered and resolved during production deployment:

### Issue 1: AIGatewayRoute backendRefs Validation Failure

**Symptom**: Kustomization `ai-gateway-routes` fails with:
```
only InferencePool from inference.networking.k8s.io group is supported
```

**Root Cause**: In v0.4.0, when `kind` and `group` are explicitly specified in AIGatewayRoute `backendRefs`, the controller ONLY accepts `InferencePool` (for self-hosted inference models). For managed services using `AIServiceBackend`, these fields must be **omitted** entirely.

**Fix**: Remove explicit `kind` and `group` from backendRefs:
```yaml
# Wrong
backendRefs:
  - name: azure-primary
    kind: AIServiceBackend
    group: aigateway.envoyproxy.io

# Correct
backendRefs:
  - name: azure-primary
```

### Issue 2: Azure Authentication Failure (Wrong Header)

**Symptom**: 401 Unauthorized responses from Azure OpenAI despite valid API key.

**Root Cause**: `type: APIKey` injects the key into the `Authorization: Bearer <key>` header. Azure OpenAI requires the key in the `api-key` header.

**Fix**: Use `type: AzureAPIKey` with `azureAPIKey.secretRef`:
```yaml
spec:
  type: AzureAPIKey
  azureAPIKey:
    secretRef:
      name: azure-secret
      namespace: envoy-ai-gateway-system
```

### Issue 3: Missing BackendTLSPolicy

**Symptom**: TLS handshake failures to Azure/MCP endpoints.

**Root Cause**: v0.4.0 requires explicit BackendTLSPolicy for TLS validation on outbound connections.

**Fix**: Create BackendTLSPolicy for each Backend:
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

### Issue 4: Rate Limiting Not Working

**Symptom**: Token-based rate limits not enforced despite BackendTrafficPolicy configured.

**Root Cause**: Two issues:
1. Missing `llmRequestCosts` in AIGatewayRoute to track token usage
2. Missing Redis rate limit backend configuration in Envoy Gateway

**Fix**:
1. Add to AIGatewayRoute:
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

2. Add to Envoy Gateway HelmRelease values:
    ```yaml
    config:
    envoyGateway:
        rateLimit:
        backend:
            type: Redis
            redis:
            url: redis.envoy-ai-gateway-system.svc.cluster.local:6379
    ```

### Issue 5: HTTPRoute Service Name Mismatch

**Symptom**: External HTTPRoute returns 503/no healthy upstream.

**Root Cause**: Service name created by Envoy Gateway matches the Gateway name (`ai-gateway`), not a custom pattern.

**Fix**: Reference `ai-gateway` service, port 80:
```yaml
backendRefs:
  - name: ai-gateway
    namespace: envoy-ai-gateway-system
    kind: Service
    port: 80
```

### Deployed Template Structure

The final deployed templates in `templates/config/kubernetes/apps/ai-gateway/`:

```
ai-gateway/
├── ks.yaml.j2                    # Parent Kustomization
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
│       ├── ocirepository.yaml.j2
│       └── gateway.yaml.j2       # AI Gateway resource
├── redis/
│   ├── ks.yaml.j2
│   └── app/
│       ├── kustomization.yaml.j2
│       └── deployment.yaml.j2
├── backends/
│   └── azure-openai/
│       ├── ks.yaml.j2
│       └── app/
│           ├── kustomization.yaml.j2
│           ├── backend.yaml.j2   # AIServiceBackend + Backend + BackendTLSPolicy + BackendSecurityPolicy
│           └── secret.sops.yaml.j2
├── mcp/
│   ├── ks.yaml.j2
│   └── app/
│       ├── kustomization.yaml.j2
│       ├── backend.yaml.j2       # Backend + BackendTLSPolicy + BackendSecurityPolicy
│       ├── mcproute.yaml.j2
│       └── secret.sops.yaml.j2
└── routes/
    ├── ks.yaml.j2
    └── app/
        ├── kustomization.yaml.j2
        ├── aigatewayroute.yaml.j2  # AIGatewayRoute with llmRequestCosts
        ├── httproute.yaml.j2       # External access route
        └── ratelimit-policy.yaml.j2
```

### Key Configuration Differences from Plan

| Aspect | Original Plan | Actual Implementation |
|--------|--------------|----------------------|
| Gateway name | `envoy-ai-gateway` | `ai-gateway` |
| BackendSecurityPolicy type | `APIKey` | `AzureAPIKey` (for Azure) |
| backendRefs in AIGatewayRoute | Explicit kind/group | Name only |
| BackendTLSPolicy | Not mentioned | Required for all backends |
| llmRequestCosts | Not in route | Required for rate limiting |
| Envoy Gateway rateLimit | Not configured | Redis backend required |
| AIServiceBackend structure | Direct host spec | backendRef to Backend resource |

### Verification Commands

After deployment, verify with:
```bash
# Check all Kustomizations are Ready
kubectl get ks -n envoy-ai-gateway-system

# Check all CRDs are Accepted
kubectl get aigatewayroutes,aiservicebackends,backendsecuritypolicies -n envoy-ai-gateway-system

# Check Gateway is Programmed
kubectl get gateways -n envoy-ai-gateway-system

# Check pods are running
kubectl get pods -n envoy-ai-gateway-system

# Check BackendTLSPolicies exist
kubectl get backendtlspolicies -n envoy-ai-gateway-system
```
