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

## Envoy AI Gateway Integration

Optional AI/LLM traffic routing via Envoy AI Gateway extension. Provides intelligent request routing to Azure OpenAI backends.

### Configuration in cluster.yaml

```yaml
# Enable AI Gateway
envoy_ai_gateway_enabled: true
envoy_ai_gateway_addr: "192.168.22.145"  # Unused IP in node_cidr

# Azure OpenAI settings
azure_openai_api_key: "<api-key>"
azure_openai_resource_name: "myopenai"      # Subdomain of endpoint
azure_openai_deployment_name: "gpt-4"
azure_openai_api_version: "2025-01-01-preview"
```

### Architecture

When enabled, the following components are deployed:
- **envoy-ai Gateway** - Dedicated Gateway with LoadBalancer IP at `llms.<domain>`
- **ClientTrafficPolicy** - Larger buffers (50Mi) for LLM payloads
- **BackendTrafficPolicy** - Extended timeouts (120s) for LLM responses
- **ai-gateway-controller** - External processor for AI routing (envoy-ai-gateway-system namespace)
- **AIGatewayRoute** - Routes `/v1/chat/completions` to Azure OpenAI
- **BackendSecurityPolicy** - Injects `api-key` header for Azure authentication

### Key Files

| File | Purpose |
|------|---------|
| `templates/config/kubernetes/apps/network/envoy-gateway/app/envoy.yaml.j2` | Gateway, traffic policies |
| `templates/config/kubernetes/apps/network/envoy-gateway/app/helmrelease.yaml.j2` | extensionManager hooks |
| `templates/config/kubernetes/apps/ai-system/envoy-ai-gateway/` | AI Gateway controller, routes |

### Critical: extensionManager Configuration

The extensionManager hooks must use the correct nested structure:

```yaml
extensionManager:
  hooks:
    xdsTranslator:
      translation:           # Nested under translation block
        listener:
          includeAll: true
        route:
          includeAll: true
        cluster:
          includeAll: true
        secret:
          includeAll: true
      post:                  # Post hooks at same level as translation
        - Translation
        - Cluster
        - Route
  service:
    fqdn:
      hostname: ai-gateway-controller.envoy-ai-gateway-system.svc.cluster.local
      port: 1063
```

### Testing

```bash
# Verify AI Gateway endpoint
curl -X POST "https://llms.<domain>/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4","messages":[{"role":"user","content":"Hello"}]}'

# Check extproc filter injection (should show envoy.filters.http.ext_proc)
kubectl get pods -n network -l gateway.envoyproxy.io/owning-gateway-name=envoy-ai
kubectl logs -n envoy-ai-gateway-system deploy/ai-gateway-controller
```

### Troubleshooting

- **502 Bad Gateway**: Check BackendTLSPolicy matches backend hostname
- **No extproc filter**: Verify extensionManager hooks use correct nested structure
- **Auth failures**: Verify BackendSecurityPolicy `api-key` header injection

See `docs/envoy-ai-gw/RESEARCH-FINDINGS.md` for detailed implementation notes.

## Envoy Gateway Admin Console

The Envoy Gateway provides a web-based Admin Console for monitoring and debugging. It is exposed at `https://envoy-ui.<domain>` via the `envoy-internal` gateway.

### Configuration

The Admin Console requires the admin server to bind to all interfaces (configured in `helmrelease.yaml.j2`):

```yaml
config:
  envoyGateway:
    admin:
      address:
        host: "0.0.0.0"
        port: 19000
```

### Access

```bash
# Via HTTPRoute (requires split DNS):
https://envoy-ui.<domain>

# Via port-forward (direct access):
kubectl port-forward -n network deploy/envoy-gateway 19000:19000
# Then open http://localhost:19000
```

### Features

- **Dashboard** - System status overview and quick navigation
- **Server Info** - Runtime details, version, uptime
- **Config Dump** - Full xDS configuration for debugging
- **Stats** - Prometheus metrics
- **Profiling** - pprof for performance analysis

**Note:** After changing admin.address configuration, restart the controller:
```bash
kubectl rollout restart deployment/envoy-gateway -n network
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
