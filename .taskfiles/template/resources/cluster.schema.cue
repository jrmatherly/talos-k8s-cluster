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

	// Azure AI Foundry - Anthropic (optional - uses US East2 resource)
	azure_anthropic_api_key?: string & !=""
	azure_anthropic_resource_name?: string & !=""

	// Azure Entra ID Authentication (optional - alternative to API key)
	azure_tenant_id?: string & !=""
	azure_client_id?: string & !=""
	azure_client_secret?: string & !=""
}

#Config
