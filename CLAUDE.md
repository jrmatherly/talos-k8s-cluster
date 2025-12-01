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
| Comments  | `#\|...\|#` |

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
- Use custom delimiters: `#{...}#`, `#%...%#`, `#|...|#`

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

## Important Warnings

1. **Never edit generated directories** (`kubernetes/`, `talos/`, `bootstrap/`) directly
2. **Always run `task configure`** after changing `cluster.yaml`, `nodes.yaml`, or templates
3. **Commit changes before running `task configure`** as it overwrites generated files
4. **BGP requires all three settings**: `cilium_bgp_router_addr`, `cilium_bgp_router_asn`, `cilium_bgp_node_asn`
5. **Helm chart extraZonePlugins/extraConfig** often REPLACES defaults rather than extending - include all required plugins explicitly
