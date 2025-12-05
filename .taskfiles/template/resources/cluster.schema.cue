package config

import (
	"net"
)

#Config: {
	node_cidr: net.IPCIDR & !=cluster_pod_cidr & !=cluster_svc_cidr
	node_dns_servers?: [...net.IPv4]
	node_ntp_servers?: [...net.IPv4]
	k8s_gateway_fallback_dns?: [...net.IPv4]
	node_default_gateway?: net.IPv4 & !=""
	node_vlan_tag?: string & !=""
	cluster_pod_cidr: *"10.42.0.0/16" | net.IPCIDR & !=node_cidr & !=cluster_svc_cidr
	cluster_svc_cidr: *"10.43.0.0/16" | net.IPCIDR & !=node_cidr & !=cluster_pod_cidr
	cluster_api_addr: net.IPv4
	cluster_api_tls_sans?: [...net.FQDN]
	cluster_gateway_addr: net.IPv4 & !=cluster_api_addr & !=cluster_dns_gateway_addr & !=cloudflare_gateway_addr
	cluster_dns_gateway_addr: net.IPv4 & !=cluster_api_addr & !=cluster_gateway_addr & !=cloudflare_gateway_addr
	repository_name: string
	repository_branch?: string & !=""
	repository_visibility?: *"public" | "private"
	cloudflare_domains: [...net.FQDN] & [_, ...]  // At least one domain required
	cloudflare_token: string
	cloudflare_gateway_addr: net.IPv4 & !=cluster_api_addr & !=cluster_gateway_addr & !=cluster_dns_gateway_addr
	cilium_bgp_router_addr?: net.IPv4 & !=""
	cilium_bgp_router_asn?: string & !=""
	cilium_bgp_node_asn?: string & !=""
	cilium_loadbalancer_mode?: *"dsr" | "snat"

	// Control Plane Scheduling
	allow_scheduling_on_control_planes?: *true | bool  // Allow workloads on control plane nodes

	// Proxmox CSI Integration (required for Proxmox storage)
	proxmox_api_url?: string & =~"^https?://.+/api2/json$"
	proxmox_insecure?: *true | bool
	proxmox_region?: string & !=""
	proxmox_storage?: string & !=""
	proxmox_csi_token_id?: string & =~"^.+@.+!.+$"  // Format: user@realm!token
	proxmox_csi_token_secret?: string & !=""

	// Proxmox CCM Integration (Approach B only - skip for Approach A)
	proxmox_ccm_token_id?: string & =~"^.+@.+!.+$"  // Format: user@realm!token
	proxmox_ccm_token_secret?: string & !=""

	// Envoy AI Gateway Configuration (optional - for AI/LLM routing)
	envoy_ai_gateway_enabled?: bool
	envoy_ai_gateway_addr?: net.IPv4 & !=cluster_api_addr & !=cluster_gateway_addr & !=cluster_dns_gateway_addr & !=cloudflare_gateway_addr

	// Azure OpenAI - US East Region (optional)
	azure_openai_us_east_api_key?: string & !=""
	azure_openai_us_east_resource_name?: string & !=""

	// Azure OpenAI - US East2 Region (optional)
	azure_openai_us_east2_api_key?: string & !=""
	azure_openai_us_east2_resource_name?: string & !=""

	// Azure Entra ID Authentication (optional - alternative to API key)
	azure_tenant_id?: string & !=""
	azure_client_id?: string & !=""
	azure_client_secret?: string & !=""

	// Observability Stack Configuration (optional - Prometheus/Grafana for K8s metrics)
	observability_enabled?: bool
	grafana_admin_password?: string & !=""

	// Prometheus configuration
	prometheus_retention?: string & !=""        // e.g., "7d"
	prometheus_retention_size?: string & !=""   // e.g., "45GB"
	prometheus_storage_size?: string & !=""     // e.g., "50Gi"
	prometheus_storage_class?: string & !=""    // e.g., "proxmox-csi"
	prometheus_replicas?: int & >=1
	prometheus_alertmanager_replicas?: int & >=1
	alertmanager_storage_size?: string & !=""
	grafana_storage_size?: string & !=""

	// Traceloop Full Platform Configuration (LLM Observability)
	traceloop_enabled?: bool
	traceloop_hub_enabled?: bool
	traceloop_hub_version?: string & !=""       // e.g., "v0.7.2"
	traceloop_hub_replicas?: int & >=1
	traceloop_hub_cpu_limit?: string & !=""
	traceloop_hub_cpu_request?: string & !=""
	traceloop_hub_memory_limit?: string & !=""
	traceloop_hub_memory_request?: string & !=""
	traceloop_openai_api_key?: string & !=""
	traceloop_anthropic_api_key?: string & !=""

	// OIDC SSO Configuration (optional - for Gateway authentication)
	oidc_enabled?: bool

	// Google OIDC Configuration
	oidc_google_enabled?: bool
	oidc_google_client_id?: string & !=""
	oidc_google_client_secret?: string & !=""

	// Microsoft Entra ID OIDC Configuration
	oidc_entra_enabled?: bool
	oidc_entra_tenant_id?: string & !=""        // UUID format tenant ID
	oidc_entra_client_id?: string & !=""        // Application (client) ID
	oidc_entra_client_secret?: string & !=""

	// GitHub OAuth Configuration (uses oauth2-proxy for ext_authz)
	oidc_github_enabled?: bool
	oidc_github_client_id?: string & !=""
	oidc_github_client_secret?: string & !=""
	oidc_github_org?: string & !=""             // Restrict to GitHub organization members
	oidc_github_team?: string & !=""            // Restrict to specific teams (comma-separated)

	// OIDC Target Configuration
	oidc_target_gateways?: [...string & !=""]   // Gateway names to protect (e.g., ["envoy-internal", "envoy-external"])
	oidc_cookie_domain?: string & !=""          // Cookie domain for cross-subdomain SSO
}

#Config
