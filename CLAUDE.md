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

Control plane scheduling:
- `allow_scheduling_on_control_planes` - Boolean (default: `true`). When `true`, removes the `node-role.kubernetes.io/control-plane:NoSchedule` taint from control plane nodes, allowing regular workloads to run there. Set to `false` for production clusters with dedicated worker nodes.

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

# Azure OpenAI - US East Region (Phase 1)
azure_openai_us_east_api_key: "<api-key>"
azure_openai_us_east_resource_name: "myopenai"  # Subdomain of endpoint

# Azure OpenAI - US East2 Region (Phase 2)
azure_openai_us_east2_api_key: "<api-key>"
azure_openai_us_east2_resource_name: "ets-east-us2"  # Subdomain of endpoint
```

### Multi-Model Architecture

The AI Gateway supports multiple backends with appropriate timeouts per model type.

#### Phase 1: Azure OpenAI US East ✅

| Model Type | Models | Timeout | AIServiceBackend |
|------------|--------|---------|------------------|
| Chat | gpt-4.1, gpt-4.1-nano, gpt-4o-mini | 120s | azure-openai-us-east-chat |
| Reasoning | o3, o4-mini | 300s | azure-openai-us-east-reasoning |
| Embedding | text-embedding-3-small, text-embedding-ada-002 | 60s | azure-openai-us-east-embedding |

#### Phase 2: Azure OpenAI US East2 ✅

| Model Type | Models | Timeout | AIServiceBackend |
|------------|--------|---------|------------------|
| Chat | gpt-5, gpt-5-nano | 120s | azure-openai-us-east2-chat |
| Thinking | gpt-5-chat, gpt-5.1-chat | 300s | azure-openai-us-east2-chat-thinking |
| Chat (April) | gpt-5-mini, gpt-5.1 | 120s | azure-openai-us-east2-chat-apr |
| Codex | gpt-5.1-codex, gpt-5.1-codex-mini | 180s | azure-openai-us-east2-codex |
| Embedding | text-embedding-3-large | 60s | azure-openai-us-east2-embedding |

**Important:** O-series reasoning models require `max_completion_tokens` instead of `max_tokens`.

### Architecture

When enabled, the following components are deployed:
- **envoy-ai Gateway** - Dedicated Gateway with LoadBalancer IP at `llms.<domain>`
- **ClientTrafficPolicy** - Larger buffers (50Mi) for LLM payloads
- **BackendTrafficPolicy** - Extended timeouts (120s) for LLM responses
- **ai-gateway-controller** - External processor for AI routing (envoy-ai-gateway-system namespace)
- **AIGatewayRoute** - Routes requests to appropriate backend based on `x-ai-eg-model` header
- **AIServiceBackend** - Per-model-type schema configuration (chat, reasoning, embedding)
- **BackendSecurityPolicy** - Injects `api-key` header for Azure authentication

### Key Files

| File | Purpose |
|------|---------|
| `templates/config/kubernetes/apps/network/envoy-gateway/app/envoy.yaml.j2` | Gateway, traffic policies |
| `templates/config/kubernetes/apps/network/envoy-gateway/app/helmrelease.yaml.j2` | extensionManager hooks |
| `templates/config/kubernetes/apps/ai-system/azure-openai-us-east/` | Backend, routes, auth for US East (Phase 1) |
| `templates/config/kubernetes/apps/ai-system/azure-openai-us-east2/` | Backend, routes, auth for US East2 (Phase 2) |

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

The `x-ai-eg-model` header determines which model/backend handles the request.

```bash
# Phase 1: Test GPT-4.1-nano (US East chat model)
curl -s -X POST "https://llms.<domain>/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "x-ai-eg-model: gpt-4.1-nano" \
  -d '{"model": "gpt-4.1-nano", "messages": [{"role": "user", "content": "Hello"}]}'

# Phase 1: Test O3 reasoning model (300s timeout, requires max_completion_tokens)
curl -s -X POST "https://llms.<domain>/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "x-ai-eg-model: o3" \
  -d '{"model": "o3", "messages": [{"role": "user", "content": "What is 15 * 23?"}], "max_completion_tokens": 500}'

# Phase 2: Test GPT-5 (US East2 chat model)
curl -s -X POST "https://llms.<domain>/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "x-ai-eg-model: gpt-5" \
  -d '{"model": "gpt-5", "messages": [{"role": "user", "content": "Hello"}]}'

# Phase 2: Test GPT-5.1-codex (code model)
curl -s -X POST "https://llms.<domain>/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "x-ai-eg-model: gpt-5.1-codex" \
  -d '{"model": "gpt-5.1-codex", "messages": [{"role": "user", "content": "Write a hello world"}]}'

# Test embeddings (Phase 1: small, Phase 2: large)
curl -s -X POST "https://llms.<domain>/v1/embeddings" \
  -H "Content-Type: application/json" \
  -H "x-ai-eg-model: text-embedding-3-large" \
  -d '{"model": "text-embedding-3-large", "input": "Hello world"}'

# Check AI Gateway resources
kubectl get aigatewayroute,aiservicebackend,backendsecuritypolicy -n ai-system
kubectl logs -n envoy-ai-gateway-system deploy/ai-gateway-controller
```

See `docs/envoy-ai-gateway-testing.md` for complete test commands for all models.

### Troubleshooting

- **502 Bad Gateway**: Check BackendTLSPolicy matches backend hostname
- **No extproc filter**: Verify extensionManager hooks use correct nested structure
- **Auth failures**: Verify BackendSecurityPolicy `api-key` header injection
- **"No matching route found"**: Wait several minutes for xDS propagation, then restart gateway pods:
  ```bash
  kubectl rollout restart deployment/envoy-gateway -n network
  kubectl delete pods -n network -l gateway.envoyproxy.io/owning-gateway-name=envoy-ai
  ```

**Important:** After configuration changes, xDS propagation can take several minutes. The AI Gateway controller must process the new configuration and inject the extproc filter into the Envoy proxy.

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

## OIDC SSO Integration

Unified Single Sign-On (SSO) authentication for cluster applications via Keycloak and Envoy Gateway SecurityPolicy. All identity providers (Google, Entra ID, GitHub) are federated through Keycloak.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Identity Providers                            │
│  ┌──────────┐    ┌───────────┐    ┌──────────┐                      │
│  │  Google  │    │ Entra ID  │    │  GitHub  │                      │
│  └────┬─────┘    └─────┬─────┘    └────┬─────┘                      │
│       └────────────────┼───────────────┘                            │
│                        ▼                                             │
│               ┌────────────────┐                                     │
│               │    Keycloak    │  auth.<domain> via envoy-auth      │
│               │  (OAuth 2.1)   │  (NO OIDC SecurityPolicy)          │
│               └────────┬───────┘                                     │
│                        │                                             │
│         ┌──────────────┼──────────────┐                             │
│         ▼              │              ▼                              │
│  ┌─────────────┐       │       ┌─────────────┐                      │
│  │envoy-internal│       │       │envoy-external│                      │
│  │oidc-keycloak│       │       │oidc-keycloak│                      │
│  │  -internal  │       │       │  -external  │                      │
│  └─────────────┘       │       └─────────────┘                      │
│  Callback:             │       Callback:                            │
│  auth-internal.<domain>│       auth-external.<domain>               │
└─────────────────────────────────────────────────────────────────────┘
```

### Configuration in cluster.yaml

```yaml
# Enable OIDC SSO integration (requires mcp_gateway_enabled=true for Keycloak)
oidc_enabled: true
mcp_gateway_enabled: true

# Auth Gateway (dedicated IP for Keycloak - no OIDC policy applied)
auth_gateway_addr: "192.168.1.155"  # Unused IP in node_cidr

# Keycloak OIDC client secret (for Envoy Gateway SecurityPolicy)
keycloak_oidc_client_secret: "xxx"

# Google identity provider (federated via Keycloak)
oidc_google_enabled: true
oidc_google_client_id: "123456789-xxx.apps.googleusercontent.com"
oidc_google_client_secret: "GOCSPX-xxx"

# Microsoft Entra ID identity provider (federated via Keycloak)
oidc_entra_enabled: true
oidc_entra_tenant_id: "12345678-1234-1234-1234-123456789abc"
oidc_entra_client_id: "87654321-4321-4321-4321-cba987654321"
oidc_entra_client_secret: "xxx"

# GitHub identity provider (federated via Keycloak)
oidc_github_enabled: true
oidc_github_client_id: "Iv1.xxx"
oidc_github_client_secret: "xxx"
oidc_github_org: "my-org"          # Optional: restrict to org members
oidc_github_team: "devs,admins"    # Optional: restrict to specific teams

# Cookie domain for SSO
oidc_cookie_domain: "example.com"
```

### Gateway Configuration

| Gateway | IP Address | Purpose | OIDC Policy |
|---------|------------|---------|-------------|
| `envoy-auth` | `auth_gateway_addr` | Keycloak login UI at `auth.<domain>` | None (prevents login loop) |
| `envoy-internal` | `cluster_gateway_addr` | Internal apps (split DNS) | `oidc-keycloak-internal` |
| `envoy-external` | `cloudflare_gateway_addr` | External apps (Cloudflare) | `oidc-keycloak-external` |

### Key Files

| File | Purpose |
|------|---------|
| `templates/config/kubernetes/apps/network/envoy-gateway/app/envoy.yaml.j2` | Gateway definitions including envoy-auth |
| `templates/config/kubernetes/apps/network/envoy-gateway/app/oidc-keycloak.yaml.j2` | Unified OIDC SecurityPolicies for internal/external |
| `templates/config/kubernetes/apps/network/envoy-gateway/app/oidc-keycloak-secret.sops.yaml.j2` | OIDC client secret |
| `templates/config/kubernetes/apps/auth-system/keycloak/` | Keycloak deployment with identity federation |

### Testing

```bash
# Check OIDC SecurityPolicies
kubectl get securitypolicy -n network
kubectl describe securitypolicy oidc-keycloak-internal -n network
kubectl describe securitypolicy oidc-keycloak-external -n network

# Check Keycloak and auth gateway
kubectl get pods -n auth-system -l app=keycloak
kubectl get gateway envoy-auth -n network

# Test Keycloak OIDC discovery
curl -s https://auth.<domain>/realms/k8s-cluster/.well-known/openid-configuration | jq

# Test authentication flow
# Navigate to a protected app (e.g., https://grafana.<domain>)
# You should be redirected to Keycloak, then choose your identity provider
```

### Callback URL Configuration

When setting up identity providers in their respective portals, register these callback URLs:

| Provider | Callback URL (Register in Provider Portal) |
|----------|-------------------------------------------|
| **Google** | `https://auth.<domain>/realms/k8s-cluster/broker/google/endpoint` |
| **Entra ID** | `https://auth.<domain>/realms/k8s-cluster/broker/microsoft/endpoint` |
| **GitHub** | `https://auth.<domain>/realms/k8s-cluster/broker/github/endpoint` |

These URLs point to Keycloak's identity broker endpoints. The IdP alias names (`google`, `microsoft`, `github`) are defined in `realm-config.yaml.j2`.

**Note:** The Envoy Gateway callback URLs (`auth-internal.<domain>/oauth2/callback`, `auth-external.<domain>/oauth2/callback`) are internal to the cluster and do NOT need to be registered in provider portals.

### Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Redirect loop | Keycloak behind OIDC-protected gateway | Verify Keycloak uses envoy-auth (not envoy-external) |
| Cookie domain mismatch | Wrong oidc_cookie_domain | Set `oidc_cookie_domain` to your primary domain |
| 403 after login | User not authorized | Check Keycloak realm roles/groups |
| Callback URL error | Redirect URI not registered | Add callback URLs to Keycloak client settings |
| IdP not showing | Identity provider not enabled | Enable `oidc_*_enabled` in cluster.yaml |

### Provider Setup Guides

See the detailed setup documentation for each provider:
- `docs/oidc-google-setup.md` - Google Cloud Console OAuth setup for Keycloak federation
- `docs/oidc-entra-setup.md` - Microsoft Entra ID app registration for Keycloak federation
- `docs/oidc-github-setup.md` - GitHub OAuth application setup for Keycloak federation
- `docs/envoy-gateway-oidc-sso.md` - Overall architecture and implementation

## MCP Authorization Gateway

Optional OAuth 2.1 Authorization Gateway for Model Context Protocol (MCP) servers. Provides centralized authentication, JWT validation, and policy enforcement for MCP tool invocations.

### Architecture

The MCP Gateway implements the full MCP authorization specification with:
- **Keycloak** - OAuth 2.1 Authorization Server with identity federation (Google, Entra ID, GitHub)
- **PostgreSQL** - Keycloak persistent storage
- **Redis** - MCP session state management
- **Envoy MCP Gateway** - Dedicated gateway with JWT validation and rate limiting

### Configuration in cluster.yaml

```yaml
# Enable MCP Gateway
mcp_gateway_enabled: true
mcp_gateway_addr: "192.168.1.146"  # Unused IP in node_cidr
mcp_storage_class: "proxmox-csi"   # Storage class for PostgreSQL/Redis
mcp_request_timeout: "120s"        # Backend timeout for tool calls
mcp_rate_limit_requests: 100       # Requests per minute per client

# Keycloak Configuration
keycloak_replicas: 3               # HA deployment
keycloak_version: "26.4.7"
keycloak_realm: "k8s-cluster"
keycloak_admin_password: "secure-password"  # Encrypted with SOPS

# PostgreSQL Configuration (CloudNativePG in database namespace)
keycloak_postgres_replicas: 1
keycloak_postgres_version: "17"
keycloak_postgres_storage_size: "10Gi"
keycloak_postgres_password: "secure-password"  # Encrypted with SOPS

# Redis Configuration
redis_replicas: 1
redis_version: "7.4"
redis_storage_size: "5Gi"
redis_password: "secure-password"  # Encrypted with SOPS
```

### Key Files

| File | Purpose |
|------|---------|
| `templates/config/kubernetes/apps/auth-system/namespace.yaml.j2` | auth-system namespace |
| `templates/config/kubernetes/apps/auth-system/keycloak/` | Keycloak StatefulSet, Services, Realm Config |
| `templates/config/kubernetes/apps/database/keycloak-postgres/` | CloudNativePG PostgreSQL Cluster |
| `templates/config/kubernetes/apps/auth-system/redis/` | Redis StatefulSet |
| `templates/config/kubernetes/apps/network/envoy-gateway/app/envoy.yaml.j2` | envoy-mcp Gateway |
| `templates/config/kubernetes/apps/network/envoy-gateway/app/mcp-securitypolicy.yaml.j2` | JWT validation, rate limiting, CORS |

### Testing

```bash
# Check MCP Gateway components
kubectl get pods -n auth-system
kubectl get gateway envoy-mcp -n network
kubectl get securitypolicy mcp-jwt-auth -n network

# Test Keycloak OIDC discovery
curl -s https://auth.<domain>/realms/k8s-cluster/.well-known/openid-configuration | jq

# Test MCP endpoint with JWT
TOKEN=$(curl -s -X POST "https://auth.<domain>/realms/k8s-cluster/protocol/openid-connect/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=mcp-gateway" \
  -d "client_secret=xxx" | jq -r '.access_token')

curl -s "https://mcp.<domain>/api/v1/tools" \
  -H "Authorization: Bearer $TOKEN"
```

### Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| 401 Unauthorized | Invalid or expired JWT | Check token expiry and refresh |
| 403 Forbidden | Missing audience claim | Verify `aud: mcp-gateway` in token |
| 503 Service Unavailable | Keycloak not ready | Check PostgreSQL connection and Keycloak pods |
| Rate limited (429) | Exceeded rate limit | Wait or increase `mcp_rate_limit_requests` |

See `docs/mcp-architecture-k8s-assessment.md` for detailed architecture documentation.

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
