# Talos Kubernetes Cluster - Claude Code Configuration

This is an Infrastructure-as-Code project for deploying a Talos Linux Kubernetes cluster with Flux GitOps.

## Project Overview

Deploy a single Kubernetes cluster on bare-metal or VMs using:
- **Talos Linux** - Immutable, secure Kubernetes OS
- **Flux** - GitOps continuous deployment
- **SOPS/age** - Secret encryption
- **Cloudflare** - Tunnel and DNS management

## Directory Structure

```
.
├── cluster.yaml              # USER CONFIG: Main cluster settings
├── nodes.yaml                # USER CONFIG: Node definitions
├── Taskfile.yaml             # Main task runner config
├── makejinja.toml            # Template engine configuration
│
├── templates/                # JINJA2 TEMPLATES (source of truth)
│   ├── config/               # Templates rendered to root dirs
│   │   ├── kubernetes/       # K8s manifest templates
│   │   ├── talos/            # Talos config templates
│   │   └── bootstrap/        # Bootstrap resource templates
│   └── scripts/plugin.py     # Makejinja plugin (filters, functions)
│
├── kubernetes/               # GENERATED: Rendered K8s manifests
├── talos/                    # GENERATED: Rendered Talos configs
├── bootstrap/                # GENERATED: Rendered bootstrap files
│
├── .taskfiles/               # Task definitions by concern
│   ├── template/Taskfile.yaml    # init, configure, validate
│   ├── bootstrap/Taskfile.yaml   # talos, apps bootstrap
│   └── talos/Taskfile.yaml       # node management, upgrades
│
└── scripts/                  # Shell scripts
    ├── bootstrap-apps.sh     # App bootstrap orchestration
    └── lib/common.sh         # Shared shell utilities
```

## Critical Workflow Understanding

### Template Rendering Pipeline

**IMPORTANT**: The `kubernetes/`, `talos/`, and `bootstrap/` directories are GENERATED.

```
cluster.yaml + nodes.yaml
        ↓
   makejinja (templates/config/*.j2)
        ↓
kubernetes/, talos/, bootstrap/
```

**Never edit generated files directly.** Edit templates in `templates/config/` or the source config files (`cluster.yaml`, `nodes.yaml`).

### Jinja2 Template Syntax

This project uses **non-standard delimiters** to avoid conflicts with Helm/Go templates:

| Purpose   | Delimiter   |
|-----------|-------------|
| Variables | `#{...}#`   |
| Blocks    | `#%...%#`   |
| Comments  | `#\|...#\|` |

**IMPORTANT**: Comment delimiters use `#|` for BOTH start AND end (not `|#`). This is defined in `makejinja.toml`:
```toml
comment_start = "#|"
comment_end = "#|"
```

Example:
```yaml
# In templates/config/kubernetes/apps/network/k8s-gateway/app/helmrelease.yaml.j2
domain: #{ primary_domain }#
```

### Configuration Data Flow

The `templates/scripts/plugin.py` provides:
- **Data enrichment**: Sets defaults for optional fields
- **Custom filters**: `basename`, `nthhost`
- **Custom functions**: `age_key()`, `cloudflare_tunnel_id()`, `cloudflare_tunnel_secret()`, `github_deploy_key()`, `github_push_token()`, `talos_patches()`

Key computed values in plugin.py:
- `primary_domain` - First domain from `cloudflare_domains` array
- `k8s_gateway_fallback_dns` - Public DNS servers filtered from `node_dns_servers`
- `cilium_bgp_enabled` - Auto-enabled if all BGP keys are set
- `spegel_enabled` - Auto-enabled if more than one node

## Common Commands

```bash
# Initialize project (first time setup)
task init

# Render templates and validate configuration
task configure

# Regenerate individual Talos node configs from talconfig.yaml
# IMPORTANT: Run after 'task configure' when updating nodes.yaml
task talos:generate-config

# Bootstrap Talos cluster (new cluster)
task bootstrap:talos

# Bootstrap applications (Flux, Cilium, etc.)
task bootstrap:apps

# Force Flux to sync with Git
task reconcile

# Check cluster status
task talos:status

# Apply config changes to a node
task talos:apply-node IP=192.168.x.x

# Upgrade Talos on a node
task talos:upgrade-node IP=192.168.x.x

# Upgrade Kubernetes version
task talos:upgrade-k8s

# Debug cluster resources
task template:debug
```

## Code Style & Conventions

### YAML Files
- 2-space indentation
- UTF-8 encoding
- LF line endings
- Trailing newlines required

### Shell Scripts (scripts/*.sh)
- 4-space indentation
- Use `set -Eeuo pipefail`
- Source `lib/common.sh` for logging utilities
- ShellCheck with SC1091 and SC2155 disabled

### CUE Files (.taskfiles/template/resources/*.cue)
- Tab indentation (4-space width)
- Used for schema validation

### Template Files (*.j2)
- Follow output format conventions (YAML, shell, etc.)
- Use custom delimiters: `#{...}#`, `#%...%#`, `#|...#|`

## Key Configuration Files

### cluster.yaml (User Input)
Required fields:
- `node_cidr` - Node network CIDR
- `cluster_api_addr` - Kubernetes API VIP
- `cluster_dns_gateway_addr` - k8s_gateway LoadBalancer IP
- `cluster_gateway_addr` - Internal gateway LoadBalancer IP
- `cloudflare_gateway_addr` - External gateway LoadBalancer IP
- `repository_name` - GitHub repo (owner/repo format)
- `cloudflare_domain` - Primary domain (string or array)
- `cloudflare_token` - Cloudflare API token

Optional fields for Kgateway/AgentGateway (AI/LLM):
- `agentgateway_addr` - AgentGateway LoadBalancer IP (enables kgateway-system)
- `agentgateway_observability_enabled` - Enable metrics, access logs, alerts (default: true)
- `otel_collector_endpoint` - OTLP endpoint for distributed tracing (e.g., "otel-collector.monitoring:4317")
- `azure_openai_api_key` - Azure OpenAI API key (enables ai-system)
- `azure_openai_resource_name` - Azure OpenAI resource name
- `azure_openai_deployment_name` - Azure OpenAI deployment name
- `azure_openai_api_version` - API version (default: "2025-04-01-preview")

### nodes.yaml (User Input)
Each node requires:
- `name` - Hostname (lowercase alphanumeric with hyphens)
- `address` - Static IP within node_cidr
- `controller` - Boolean (true for control plane)
- `disk` - Device path (/dev/sda) or serial number
- `mac_addr` - Network interface MAC address
- `schematic_id` - Talos Image Factory schematic ID

Optional fields:
- `nodeLabels` - Kubernetes node labels (for CSI topology, etc.)
  ```yaml
  nodeLabels:
    topology.kubernetes.io/region: "talos-k8s"
    topology.kubernetes.io/zone: "pve01"
  ```

Note: the values above are examples only

### talconfig.yaml (Generated)
**DO NOT EDIT** - Generated from templates. Edit `nodes.yaml` and `templates/config/talos/talconfig.yaml.j2` instead.

## Secret Files (DO NOT COMMIT UNENCRYPTED)

These files contain sensitive data and must be handled carefully:
- `age.key` - SOPS encryption key (gitignored)
- `cloudflare-tunnel.json` - Tunnel credentials (gitignored)
- `github-deploy.key` - SSH deploy key (gitignored)
- `*.sops.yaml` - Encrypted secrets (safe to commit)

SOPS encryption rules in `.sops.yaml`:
- `talos/*.sops.yaml` - Full file encryption
- `kubernetes/*.sops.yaml` and `bootstrap/*.sops.yaml` - Only `data` and `stringData` fields encrypted

## Kubernetes App Structure

Each application follows the Flux Kustomization pattern:

```
kubernetes/apps/<namespace>/<app-name>/
├── ks.yaml              # Kustomization resource
└── app/
    ├── kustomization.yaml   # Kustomize config
    ├── helmrelease.yaml     # HelmRelease resource
    ├── ocirepository.yaml   # OCI source for Helm chart
    ├── httproute.yaml       # HTTPRoute for Gateway API (if needed)
    └── secret.sops.yaml     # Encrypted secrets (if needed)
```

## Helm Chart Configuration

When modifying Helm values in HelmRelease templates:
1. Check the upstream chart documentation
2. Some Helm chart options use **replace** semantics (e.g., `extraZonePlugins` in k8s-gateway replaces defaults, doesn't extend)
3. Always verify rendered output with `task configure`

## Environment Variables

Managed via `.mise.toml`:
- `KUBECONFIG` - Points to `./kubeconfig`
- `SOPS_AGE_KEY_FILE` - Points to `./age.key`
- `TALOSCONFIG` - Points to `./talos/clusterconfig/talosconfig`

## Debugging

```bash
# Check Flux status
flux check
flux get ks -A
flux get hr -A

# Check pod issues
kubectl get pods -A | grep -v Running
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>

# Talos diagnostics
talosctl -n <node-ip> dmesg
talosctl -n <node-ip> services
talosctl health

# DNS testing (after k8s-gateway deployed)
dig @<cluster_dns_gateway_addr> <hostname>.<domain>

# Hubble network observability
# CLI access (requires cilium CLI with hubble port-forward running):
cilium hubble port-forward &
hubble status
hubble observe --follow

# Web UI access:
# Via HTTPRoute: https://hubble.<domain> (requires split DNS)
# Via port-forward (local:8080 → service:80 → container:8081):
kubectl -n kube-system port-forward svc/hubble-ui 8080:80
# Then open http://localhost:8080
```

## Talos Configuration Workflow

When modifying `nodes.yaml` with changes that affect Talos machine config (nodeLabels, disk, MTU, etc.):

```bash
# 1. Edit nodes.yaml (or templates)
# 2. Render Jinja2 templates (creates talconfig.yaml)
task configure

# 3. Generate individual node configs from talconfig.yaml
task talos:generate-config

# 4. Apply to nodes
task talos:apply-node IP=192.168.x.x
```

**Why both steps?** `task configure` renders Jinja2 templates including `talconfig.yaml`, but does NOT run `talhelper genconfig`. The individual node config files in `talos/clusterconfig/` are only regenerated by `task talos:generate-config` (or during `task bootstrap:talos`).

## Proxmox CSI Integration

For Proxmox persistent storage, add to `cluster.yaml`:
- `proxmox_api_url` - API endpoint (e.g., "https://192.168.1.10:8006/api2/json")
- `proxmox_region` - Region name for topology
- `proxmox_storage` - Storage pool (e.g., "local-zfs")
- `proxmox_csi_token_id` - API token ID
- `proxmox_csi_token_secret` - API token secret

Add topology labels to each node in `nodes.yaml` (see nodeLabels above).

**Note:** CSI templates are conditionally rendered only when both `proxmox_csi_token_id` and `proxmox_csi_token_secret` are set.

## Kgateway/AgentGateway Integration (v2.1.1)

Kgateway v2.1.1 provides AI/LLM gateway capabilities via AgentGateway. This project uses the `Backend` CRD with `type: AI` or `type: Static` for backend configuration.

### Architecture

Kgateway runs alongside envoy-gateway (complement, not replace):
- **envoy-gateway**: General HTTP/HTTPS ingress (internal + external via Cloudflare)
- **kgateway/agentgateway**: AI workload routing (LLM providers)

### Namespaces
- `kgateway-system` - Control plane (kgateway, agentgateway pods)
- `ai-system` - AI workloads (Backends, HTTPRoutes, secrets)

### Configuration

Enable by setting `agentgateway_addr` in `cluster.yaml`. Add Azure OpenAI credentials to enable the ai-system namespace:

```yaml
agentgateway_addr: "192.168.22.145"
azure_openai_api_key: "your-api-key"
azure_openai_resource_name: "your-resource-name"
azure_openai_deployment_name: "gpt-4"
```

### Key Implementation Details (v2.1.1)

1. **GatewayParameters**: Kgateway creates Services from Gateway resources. To pass Cilium LB IPAM annotations, use `GatewayParameters` with `spec.kube.service.extraAnnotations` and reference via `spec.infrastructure.parametersRef` in the Gateway.

2. **TLS Listeners**: Kgateway requires exactly 1 certificateRef per HTTPS listener. Create separate listeners for each domain with hostname patterns (`*.matherly.net`, `*.spoonsofsalt.org`).

3. **Backend CRD Schema (v2.1.1)**: AI workloads use `Backend` (`agentgateway.dev/v1alpha1`) with `type: AI` or `type: Static`. Auth is configured via `spec.ai.llm.<provider>.authToken.secretRef`.

   **Azure OpenAI Backend:**
   ```yaml
   apiVersion: agentgateway.dev/v1alpha1
   kind: Backend
   metadata:
     name: azure-openai-chat
   spec:
     type: AI
     ai:
       llm:
         azureopenai:
           endpoint: "https://resource-name.openai.azure.com"  # Include https:// prefix
           deploymentName: "gpt-4"
           apiVersion: "2025-01-01-preview"
           authToken:
             kind: SecretRef
             secretRef:
               name: azure-openai-credentials  # Secret with 'Authorization' key
   ```

   **Static Backend (Cohere, etc.):**
   Static backends use `spec.static.hosts[]` and require a separate `BackendConfigPolicy` for TLS:
   ```yaml
   apiVersion: agentgateway.dev/v1alpha1
   kind: Backend
   metadata:
     name: azure-cohere-embed
   spec:
     type: Static
     static:
       hosts:
         - host: "resource.services.ai.azure.com"
           port: 443
   ---
   apiVersion: agentgateway.dev/v1alpha1
   kind: BackendConfigPolicy
   metadata:
     name: azure-cohere-embed-tls
   spec:
     targetRefs:
       - name: azure-cohere-embed
         kind: Backend
         group: agentgateway.dev
     tls:
       sni: "resource.services.ai.azure.com"
       wellKnownCACertificates: System
   ```

   **Custom Host Override (e.g., Anthropic via Azure AI Foundry):**
   ```yaml
   apiVersion: agentgateway.dev/v1alpha1
   kind: Backend
   metadata:
     name: azure-anthropic
   spec:
     type: AI
     ai:
       llm:
         anthropic:
           authToken:
             kind: SecretRef
             secretRef:
               name: azure-anthropic-credentials
           apiVersion: "2023-06-01"
           model: "claude-haiku-4-5"
         # Override host/port to Azure AI Foundry endpoint
         host: "resource-name.services.ai.azure.com"
         port: 443
   ```

4. **HTTPRoute backendRefs**: HTTPRoutes reference `Backend`:
   ```yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: HTTPRoute
   spec:
     rules:
       - backendRefs:
           - group: agentgateway.dev
             kind: Backend
             name: azure-openai-chat
             namespace: ai-system
   ```

5. **Path Configuration**: For path transformation, use HTTPRoute `URLRewrite` filter:
   ```yaml
   # In HTTPRoute - transforms /anthropic/messages -> /anthropic/v1/messages
   filters:
     - type: URLRewrite
       urlRewrite:
         path:
           type: ReplacePrefixMatch
           replacePrefixMatch: /anthropic/v1/messages
   ```

6. **Secret Format**: Use `Authorization` as the key name in the secret's stringData.

7. **Static Backend Secret Bootstrapping**: Static backends (Cohere, etc.) use `postBuild.substituteFrom` to inject API keys into HTTPRoutes. This creates a circular dependency if the secret is in the same kustomization. Solution: Create a separate `ai-secrets` kustomization that runs before backend kustomizations:
   ```yaml
   # ai-system/ai-secrets/ks.yaml - runs first, creates secrets
   dependsOn:
     - name: kgateway
       namespace: kgateway-system
   # NOTE: decryption.provider: sops is added by cluster-apps patch
   # Do NOT specify secretRef - Flux auto-discovers sops-age in flux-system

   # ai-system/azure-cohere-rerank/ks.yaml - runs after ai-secrets
   dependsOn:
     - name: ai-secrets  # Ensures secret exists before postBuild
   postBuild:
     substituteFrom:
       - kind: Secret
         name: azure-cohere-rerank-credentials
   ```

8. **ReferenceGrant Namespace and Flux targetNamespace**: When a Flux Kustomization has `targetNamespace`, it overrides the namespace in ALL resources within that kustomization. ReferenceGrants for cross-namespace secret access must be deployed via a **separate** Kustomization that targets the namespace where the secrets reside:
   ```yaml
   # ReferenceGrant must be in network namespace (where TLS secrets are)
   # Deploy via network kustomization, NOT kgateway kustomization
   apiVersion: gateway.networking.k8s.io/v1beta1
   kind: ReferenceGrant
   metadata:
     name: agentgateway-tls-secrets
     # namespace inherited from parent kustomization (network)
   spec:
     from:
       - group: gateway.networking.k8s.io
         kind: Gateway
         namespace: kgateway-system
     to:
       - group: ""
         kind: Secret
   ```

9. **AgentGateway UI**: The AgentGateway pod exposes a built-in UI on port 15000. Access via HTTPRoute at `https://agentgateway.<domain>` (requires split DNS).

### Observability

AgentGateway observability is **enabled by default** when `agentgateway_addr` is set. Disable with `agentgateway_observability_enabled: false`.

**Components deployed when enabled:**
- **ServiceMonitor**: Prometheus metrics scraping (port 15020, 30s interval)
  - Filters for `agentgateway_*`, `envoy_*`, `llm_*` metrics to reduce cardinality
- **HTTPListenerPolicy**: JSON access logging to stdout with AI-specific fields
  - Includes timing, upstream info, request headers, and `X-MODEL` header
- **PrometheusRule**: 8 alert rules for AI gateway monitoring:
  - `AIGatewayHighErrorRate` (>5% for 5m, warning)
  - `AIGatewayCriticalErrorRate` (>15% for 2m, critical)
  - `AIGatewayHighLatency` (P95 >30s, warning)
  - `AIGatewayRateLimitExceeded` (>10 req/s rate limited, warning)
  - `AIGatewayTPMApproachingLimit` (>80% of 450K TPM, warning)
  - `AIGatewayBackendUnhealthy` (<50% healthy backends, critical)
  - `AIGatewayNoTraffic` (no requests for 30m, info)
  - `AIGatewayConnectionPoolExhausted` (>90% pool usage, warning)

**Grafana Dashboards:**
Two official Kgateway dashboards are automatically provisioned:
- **Envoy Dashboard**: Data-plane metrics (request rates, latencies, errors)
- **Kgateway Operations Dashboard**: Control-plane metrics

Dashboards appear in the `kgateway` folder in Grafana (requires kube-prometheus-stack with sidecar discovery).

**Optional OTLP Tracing:**
Set `otel_collector_endpoint` in `cluster.yaml` to enable distributed tracing:
```yaml
otel_collector_endpoint: "otel-collector.monitoring:4317"
```

### Debugging Kgateway

```bash
# Check kgateway resources
kubectl get ks -n kgateway-system
kubectl get ks -n ai-system
kubectl get gateway -n kgateway-system
kubectl get gatewayparameters -n kgateway-system
kubectl get backends.agentgateway.dev -n ai-system  # AI and Static backends (v2.1.1)
kubectl get httproute -n ai-system

# Check pods and services
kubectl get pods -n kgateway-system
kubectl get svc -n kgateway-system agentgateway
kubectl get svc -n kgateway-system agentgateway-ui  # UI service on port 15000

# Verify Service has LB annotation
kubectl get svc -n kgateway-system agentgateway -o jsonpath='{.metadata.annotations}'

# Access AgentGateway UI
# Via HTTPRoute: https://agentgateway.<domain> (requires split DNS)
# Via port-forward:
kubectl -n kgateway-system port-forward svc/agentgateway-ui 15000:15000
# Then open http://localhost:15000

# Observability debugging
kubectl get servicemonitor -n kgateway-system
kubectl get prometheusrule -n kgateway-system
kubectl get httplistenerpolicy -n kgateway-system

# Check agentgateway access logs (JSON format)
kubectl logs -n kgateway-system -l app.kubernetes.io/name=agentgateway -f

# Check Prometheus alert status
kubectl get prometheusrule -n kgateway-system ai-gateway-alerts -o yaml
```

## Adding New Applications/Templates

When adding new application templates to this project, multiple files must be updated **before** running `task configure`. See the Serena memory `.serena/memories/adding-new-templates-checklist.md` for the complete checklist.

**Quick reference - files to update:**
1. `.taskfiles/template/resources/cluster.schema.cue` - CUE schema definitions
2. `.taskfiles/template/resources/cluster.sample.yaml` - Sample/documentation
3. `cluster.yaml` - **Primary config** with actual values (required for rendering)
4. `.github/tests/public.yaml` and `private.yaml` - Test configurations
5. `templates/scripts/plugin.py` - Default values and backward compatibility
6. Template files in `templates/config/kubernetes/apps/<namespace>/`
7. Parent `kustomization.yaml.j2` - Conditional includes

## Important Warnings

1. **Never edit generated directories** (`kubernetes/`, `talos/`, `bootstrap/`) directly
2. **Always run `task configure`** after changing `cluster.yaml`, `nodes.yaml`, or templates
3. **Run `task talos:generate-config`** after `task configure` when modifying `nodes.yaml` with Talos machine config changes
4. **Commit changes before running `task configure`** as it overwrites generated files
5. **BGP requires all three settings**: `cilium_bgp_router_addr`, `cilium_bgp_router_asn`, `cilium_bgp_node_asn`
6. **Helm chart extraZonePlugins/extraConfig** often REPLACES defaults rather than extending - include all required plugins explicitly
7. **Flux Kustomization dependsOn** namespaces must match where the dependency actually runs (e.g., `cilium` is in `kube-system`, not `flux-system`)
8. **Adding new templates** requires updating multiple config files first - see checklist above
