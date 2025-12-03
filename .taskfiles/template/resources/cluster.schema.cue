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

	// Kgateway / AgentGateway Integration (AI/LLM Infrastructure)
	agentgateway_addr?: net.IPv4 & !=cluster_api_addr & !=cluster_gateway_addr & !=cluster_dns_gateway_addr & !=cloudflare_gateway_addr
	agentgateway_observability_enabled?: *true | bool  // Enable metrics, access logs, and alerts
	otel_collector_endpoint?: string & =~"^[a-z0-9.-]+:[0-9]+$"  // OTLP endpoint (e.g., "otel-collector.monitoring:4317")

	// Enhancement settings
	agentgateway_prompt_guard_enabled?: *true | bool  // Enable PII/sensitive data blocking
	agentgateway_rate_limit_enabled?: *true | bool    // Enable rate limiting per backend

	// Azure OpenAI - East US2 (Primary Region) - shared API key for all backends
	azure_openai_eastus2_resource_name?: string & !=""
	azure_openai_eastus2_api_key?: string & !=""  // Single shared key for all East US2 backends
	azure_openai_eastus2_chat_deployment_name?: string & !=""
	azure_openai_eastus2_chat_api_version?: string & !=""
	azure_openai_eastus2_responses_deployment_name?: string & !=""
	azure_openai_eastus2_responses_api_version?: string & !=""
	azure_openai_eastus2_embeddings_deployment_name?: string & !=""
	azure_openai_eastus2_embeddings_api_version?: string & !=""
	azure_openai_eastus2_realtime_deployment_name?: string & !=""
	azure_openai_eastus2_realtime_api_version?: string & !=""
	azure_openai_eastus2_images_deployment_name?: string & !=""
	azure_openai_eastus2_images_api_version?: string & !=""
	azure_openai_eastus2_audio_deployment_name?: string & !=""
	azure_openai_eastus2_audio_api_version?: string & !=""

	// Azure OpenAI - East US (Secondary Region)
	azure_openai_eastus_resource_name?: string & !=""
	azure_openai_eastus_api_key?: string & !=""
	azure_openai_eastus_chat_deployment_name?: string & !=""
	azure_openai_eastus_chat_api_version?: string & !=""
	azure_openai_eastus_embeddings_deployment_name?: string & !=""
	azure_openai_eastus_embeddings_api_version?: string & !=""

	// Azure AI Foundry - Anthropic Claude
	azure_anthropic_resource_name?: string & !=""
	azure_anthropic_api_key?: string & !=""

	// Azure AI Models - Cohere
	azure_cohere_rerank_host?: string & =~"^[a-z0-9.-]+$"
	azure_cohere_rerank_api_key?: string & !=""
	azure_cohere_embed_host?: string & =~"^[a-z0-9.-]+$"
	azure_cohere_embed_api_key?: string & !=""

	// Direct Provider APIs (non-Azure) - legacy/backward compatibility
	azure_openai_api_key?: string & !=""
	azure_openai_resource_name?: string & !=""
	azure_openai_deployment_name?: string & !=""
	azure_openai_api_version?: string & !=""
	openai_api_key?: string & !=""
	anthropic_api_key?: string & !=""
}

#Config
