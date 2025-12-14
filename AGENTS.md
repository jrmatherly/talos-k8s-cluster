# AGENTS.md - Talos Kubernetes Cluster

A simple guide for AI coding agents working on this Infrastructure-as-Code project.

## Project Overview

Deploy a Kubernetes cluster on bare-metal/VMs using:
- **Talos Linux** - Immutable, secure Kubernetes OS
- **Flux** - GitOps continuous deployment
- **SOPS/age** - Secret encryption
- **Cloudflare** - Tunnel and DNS management

## Setup Commands

```bash
# Initialize project (first time)
task init

# Render templates and validate
task configure -y -y

# Regenerate Talos node configs (after nodes.yaml changes)
task talos:generate-config

# Bootstrap new cluster
task bootstrap:talos
task bootstrap:apps

# Force Flux sync
task reconcile

# Apply config to a node
task talos:apply-node IP=192.168.x.x

# Check status
task talos:status
flux check
flux get ks -A
```

## Critical Workflow

**Template Rendering Pipeline:**
```
cluster.yaml + nodes.yaml → makejinja → kubernetes/, talos/, bootstrap/
```

**NEVER edit generated directories** (`kubernetes/`, `talos/`, `bootstrap/`) directly. Edit templates in `templates/config/` or source configs (`cluster.yaml`, `nodes.yaml`).

**Jinja2 Custom Delimiters** (to avoid Helm/Go conflicts):

| Purpose   | Delimiter   |
|-----------|-------------|
| Variables | `#{...}#`   |
| Blocks    | `#%...%#`   |
| Comments  | `#\|...#\|` |

## Code Style

### YAML Files
- 2-space indentation, UTF-8, LF line endings, trailing newlines

### Shell Scripts (scripts/*.sh)
- 4-space indentation
- Use `set -Eeuo pipefail`
- Source `lib/common.sh` for logging

### Template Files (*.j2)
- Follow output format conventions
- Use custom delimiters: `#{...}#`, `#%...%#`, `#|...#|`

## Key Configuration Files

| File | Purpose |
|------|---------|
| `cluster.yaml` | Main cluster settings (user config) |
| `nodes.yaml` | Node definitions (user config) |
| `templates/config/` | Jinja2 templates (source of truth) |
| `templates/scripts/plugin.py` | Template filters and functions |

## Testing & Validation

```bash
# Validate templates
task configure -y

# Check Flux status
flux check
flux get ks -A
flux get hr -A

# Check pods
kubectl get pods -A | grep -v Running

# Talos diagnostics
talosctl health
talosctl -n <node-ip> services
```

## Security Considerations

- **Never commit unencrypted secrets** - Use SOPS/age encryption
- Secret files (`age.key`, `cloudflare-tunnel.json`, `github-deploy.key`) are gitignored
- `*.sops.yaml` files are encrypted and safe to commit

## Adding New Applications

When adding new application templates, update these files **before** `task configure -y`:
1. `.taskfiles/template/resources/cluster.schema.cue` - CUE schema
2. `cluster.yaml` - Primary config with values
3. `templates/scripts/plugin.py` - Default values
4. Template files in `templates/config/kubernetes/apps/<namespace>/`
5. Parent `kustomization.yaml.j2` - Conditional includes

See `.serena/memories/adding-new-templates-checklist.md` for complete checklist.

## Important Warnings

1. **Never edit generated directories** directly
2. **Always run `task configure -y`** after config/template changes
3. **Run `task talos:generate-config`** after nodes.yaml changes affecting Talos
4. **Commit before `task configure -y`** - it overwrites generated files
5. **Helm extraZonePlugins/extraConfig** often REPLACES defaults, not extends
6. **Cilium socket-based LB and NetworkPolicy** - Standard `ipBlock` rules DON'T work for LoadBalancer IPs or K8s API; use CiliumNetworkPolicy with `fromEntities: world` / `toEntities: world` / `toEntities: kube-apiserver`. Must allow BOTH service port AND container port (e.g., 53 AND 1053)
7. **agentgateway only supports chat completions** - Embeddings API not supported; use direct Azure endpoint
8. **agentgateway HTTPRoute path ordering** - Longest paths first to prevent path collisions
9. **AgentgatewayPolicy CRD schema** - Use `spec.backend.mcp.authentication` and `spec.traffic.cors`; CORS `maxAge` is integer, `allowOrigins` cannot use wildcard ports

## Extended Documentation

For detailed component documentation, see:
- `docs/ai-context/litellm.md` - LiteLLM proxy (multi-provider routing, credential management, Prometheus metrics)
- `docs/ai-context/envoy-ai-gateway.md` - Envoy AI Gateway integration
- `docs/ai-context/agentgateway-mcp.md` - agentgateway/kgateway unified AI Gateway (LLM routing, MCP OAuth, RBAC, FinOps)
- `docs/ai-context/cilium-networkpolicy.md` - CiliumNetworkPolicy for K8s API access
- `docs/ai-context/obot-networking.md` - obot MCP server networking
- `docs/ai-context/kagent-a2a.md` - kagent A2A networking
- `docs/ai-context/imagevolume-cnpg.md` - ImageVolume for CloudNativePG extensions

For Claude-specific context, see `CLAUDE.md`.
