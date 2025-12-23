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

**IMPORTANT**: Comment delimiters use `#|` for BOTH start AND end (not `|#`). This is defined in `makejinja.toml`.

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
task configure -y

# Regenerate individual Talos node configs from talconfig.yaml
# IMPORTANT: Run after 'task configure -y' when updating nodes.yaml
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

Control plane scheduling:
- `allow_scheduling_on_control_planes` - Boolean (default: `true`). When `true`, removes the `node-role.kubernetes.io/control-plane:NoSchedule` taint from control plane nodes.

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
3. Always verify rendered output with `task configure -y`

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
cilium hubble port-forward &
hubble status
hubble observe --follow
```

## Talos Configuration Workflow

When modifying `nodes.yaml` with changes that affect Talos machine config (nodeLabels, disk, MTU, etc.):

```bash
# 1. Edit nodes.yaml (or templates)
# 2. Render Jinja2 templates (creates talconfig.yaml)
task configure -y

# 3. Generate individual node configs from talconfig.yaml
task talos:generate-config

# 4. Apply to nodes
task talos:apply-node IP=192.168.x.x
```

**Why both steps?** `task configure -y` renders Jinja2 templates including `talconfig.yaml`, but does NOT run `talhelper genconfig`. The individual node config files in `talos/clusterconfig/` are only regenerated by `task talos:generate-config`.

## Proxmox CSI Integration

For Proxmox persistent storage, add to `cluster.yaml`:
- `proxmox_api_url` - API endpoint (e.g., "https://192.168.1.10:8006/api2/json")
- `proxmox_region` - Region name for topology
- `proxmox_storage` - Storage pool (e.g., "local-zfs")
- `proxmox_csi_token_id` - API token ID
- `proxmox_csi_token_secret` - API token secret

Add topology labels to each node in `nodes.yaml`. CSI templates are conditionally rendered only when both `proxmox_csi_token_id` and `proxmox_csi_token_secret` are set.

## Adding New Applications/Templates

When adding new application templates to this project, multiple files must be updated **before** running `task configure -y`. See `.serena/memories/adding-new-templates-checklist.md` for the complete checklist.

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
2. **Always run `task configure -y`** after changing `cluster.yaml`, `nodes.yaml`, or templates
3. **Run `task talos:generate-config`** after `task configure -y` when modifying `nodes.yaml` with Talos machine config changes
4. **Commit changes before running `task configure -y`** as it overwrites generated files
5. **BGP requires all three settings**: `cilium_bgp_router_addr`, `cilium_bgp_router_asn`, `cilium_bgp_node_asn`
6. **Helm chart extraZonePlugins/extraConfig** often REPLACES defaults rather than extending - include all required plugins explicitly
7. **Flux Kustomization dependsOn** - Parent Kustomize `namespace:` field overrides child ks.yaml `metadata.namespace`. For dependsOn: omit namespace for same-parent dependencies, only specify for cross-namespace (e.g., `cilium` in `kube-system`)
8. **Adding new templates** requires updating multiple config files first - see checklist above
9. **obot service port must be 80** - MCP servers generate token exchange URLs without explicit ports (defaulting to 80)
10. **obot multi-replica requires S3 storage** - Proxmox CSI only supports RWO (ReadWriteOnce); use `obot_workspace_provider: s3` with MinIO for multiple replicas
11. **NetworkPolicies require ports on BOTH sides** - Traffic between namespaces must be allowed by both egress (source) AND ingress (destination) policies
12. **Cilium socket-based LB and NetworkPolicy** - Standard `ipBlock` rules DON'T work for LoadBalancer IPs; use CiliumNetworkPolicy with `fromEntities: world` / `toEntities: world` instead. Must allow BOTH service port AND container port (e.g., 53 AND 1053 for k8s-gateway)
13. **agentgateway only supports chat completions** - Embeddings API not supported; Gateway API RequestHeaderModifier doesn't support secret refs for API key injection
14. **agentgateway HTTPRoute path ordering** - Use PathPrefix matching with longest paths first to prevent `/azure/gpt5` from matching `/azure/gpt51`
15. **AgentgatewayPolicy CRD schema** - Use `spec.backend.mcp.authentication` and `spec.traffic.cors` (NOT `spec.policy.*`); provider is enum (`Keycloak`), not object; CORS `maxAge` is integer, `allowOrigins` cannot use wildcard ports
16. **MinIO chart ServiceMonitor** - Don't add `release` to `metrics.serviceMonitor.additionalLabels` - the chart already sets `release: {{ .Release.Name }}`, causing duplicate key errors with Flux
17. **Flux Kustomization substituteFrom** - Only use `cluster-secrets` Secret (exists in each namespace); `cluster-settings` ConfigMap doesn't exist in this cluster
18. **MinIO v3 metrics require custom ServiceMonitor** - Helm chart only scrapes v2 endpoints; for community v3 Grafana dashboard, deploy separate ServiceMonitor scraping `/minio/metrics/v3/*` paths
19. **Cognee migration architecture bug** - Cognee's entrypoint.sh runs Alembic migrations BEFORE SQLAlchemy creates base tables; init container workaround pre-creates some tables but deployment may still fail; see `docs/ai-context/cognee-deployment.md`
20. **Cognee frontend requires GHCR images** - Uses `ghcr.io/jrmatherly/cognee` and `ghcr.io/jrmatherly/cognee-frontend`; frontend requires `cognee_frontend_enabled: true` and optionally Auth0 credentials for authentication
21. **UnPoller chart version suffix** - Use `2.11.2-Chart6` (not `2.11.2`); chart doesn't support `envFrom` natively, use Flux `postRenderers` to inject from `cluster-secrets`
22. **Proxmox Grafana dashboards** - Community dashboards (16060, 13307) use `${DS_SHIFT-METRICS}` variable that doesn't auto-resolve; import manually via Grafana UI and map to `VictoriaMetrics` datasource
23. **OTEL collector OTLP endpoint** - Don't append `/v1/logs` to VictoriaLogs endpoint; OTLP exporter auto-appends it. Use: `http://victoria-logs-server.observability.svc.cluster.local:9428/insert/opentelemetry`
24. **VictoriaMetrics ports** - VMSingle uses port **8428**, VMAgent uses port **8429**. Don't confuse them! Service names: `vmsingle-vmstack:8428` (storage), `vmagent-vmstack:8429` (collection)

## Extended Documentation

For detailed component documentation, see:
- `docs/ai-context/kgateway.md` - kgateway controller (Gateway API, Envoy data plane, OIDC, traffic policies)
- `docs/ai-context/agentgateway-mcp.md` - agentgateway unified AI Gateway (LLM routing, MCP OAuth, RBAC, FinOps)
- `docs/ai-context/litellm.md` - LiteLLM proxy (multi-provider routing, credential management, Prometheus metrics)
- `docs/ai-context/cognee-deployment.md` - Cognee Graph RAG deployment (Neo4j + pgvector, migration workarounds, known issues)
- `docs/ai-context/cilium-networkpolicy.md` - CiliumNetworkPolicy patterns for K8s API access
- `docs/ai-context/obot-networking.md` - obot MCP server networking (port architecture, NetworkPolicy)
- `docs/ai-context/kagent-a2a.md` - kagent A2A networking (controller→agent, ModelConfig)
- `docs/ai-context/imagevolume-cnpg.md` - ImageVolume feature gate for CloudNativePG extensions
- `docs/ai-context/unifi-metrics.md` - UnPoller UniFi monitoring (postRenderers, cluster-secrets pattern)
- `docs/ai-context/proxmox-metrics.md` - Proxmox VE metrics (InfluxDB protocol, dashboard workarounds)

For the universal agent guide, see `AGENTS.md`.
