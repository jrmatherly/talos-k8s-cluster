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

	// OneDev Configuration (Git Server with CI/CD)
	onedev_enabled?: bool
	onedev_admin_password?: string & !=""
	onedev_storage_size?: string & !=""         // e.g., "100Gi"
	onedev_storage_class?: string & !=""        // e.g., "proxmox-csi"
	onedev_database_type?: "mysql" | "postgresql" | "mariadb" | "mssql"
	onedev_database_host?: string & !=""
	onedev_database_port?: string & !=""
	onedev_database_name?: string & !=""
	onedev_database_user?: string & !=""
	onedev_database_password?: string & !=""
	onedev_ssh_port?: int & >=1 & <=65535
	onedev_cpu_limit?: string & !=""
	onedev_memory_limit?: string & !=""
	onedev_cpu_request?: string & !=""
	onedev_memory_request?: string & !=""

	// WorkOS AuthKit Configuration (OAuth 2.1 / MCP authentication)
	workos_client_id?: string & !=""
	workos_client_secret?: string & !=""
	workos_subdomain?: string & !=""            // e.g., "your-subdomain" for your-subdomain.authkit.app

	// MCP Gateway Configuration (Model Context Protocol)
	mcp_gateway_enabled?: bool
	mcp_gateway_addr?: net.IPv4 & !=cluster_api_addr & !=cluster_gateway_addr & !=cluster_dns_gateway_addr & !=cloudflare_gateway_addr & !=envoy_ai_gateway_addr
	mcp_session_timeout?: int & >=60            // Session timeout in seconds, default 3600

	// Keycloak Configuration (OIDC Authentication Provider)
	keycloak_enabled?: bool
	keycloak_admin_password?: string & !=""
	keycloak_db_password?: string & !=""
	keycloak_replicas?: int & >=1               // Number of Keycloak replicas (default: 2)
	keycloak_cpu_request?: string & !=""        // e.g., "250m"
	keycloak_memory_request?: string & !=""     // e.g., "512Mi"
	keycloak_cpu_limit?: string & !=""          // e.g., "1000m"
	keycloak_memory_limit?: string & !=""       // e.g., "1Gi"
	keycloak_postgresql_enabled?: bool          // Enable built-in CloudNativePG PostgreSQL (default: true)
	keycloak_postgresql_replicas?: int & >=1    // PostgreSQL replicas (default: 3)
	keycloak_postgresql_storage_size?: string & !=""  // e.g., "10Gi"
	keycloak_oidc_client_secret?: string & !="" // OIDC client secret for Envoy Gateway integration
	keycloak_oidc_cookie_domain?: string & !="" // Cookie domain for SSO across subdomains (optional)

	// Keycloak Entra ID Identity Provider (optional - federation with Microsoft Entra ID)
	keycloak_entra_id_enabled?: bool            // Enable Microsoft Entra ID as identity provider
	keycloak_entra_id_tenant_id?: string & !="" // Azure Entra ID tenant ID (GUID)
	keycloak_entra_id_client_id?: string & !="" // Azure App Registration client ID (GUID)
	keycloak_entra_id_client_secret?: string & !="" // Azure App Registration client secret

	// agentgateway Configuration (MCP 2025-11-25 OAuth Proxy)
	// Wraps Keycloak for MCP spec-compliant authentication (DCR, CIMD, Protected Resource Metadata)
	agentgateway_enabled?: bool                 // Enable agentgateway for MCP authentication
	agentgateway_addr?: net.IPv4 & !=cluster_api_addr & !=cluster_gateway_addr & !=cluster_dns_gateway_addr & !=cloudflare_gateway_addr & !=envoy_ai_gateway_addr & !=mcp_gateway_addr
	agentgateway_scopes?: [...string]           // OAuth scopes (default: openid, profile, email, offline_access)
	keycloak_agentgateway_client_secret?: string & !="" // Client secret for agentgateway (defaults to keycloak_oidc_client_secret)

	// obot Configuration (Multi-tenant MCP Gateway)
	// Self-hosted AI agent platform with Entra ID authentication
	obot_enabled?: bool                         // Enable obot MCP gateway
	obot_db_password?: string & !=""            // PostgreSQL password for obot database
	obot_cookie_secret?: string & !=""          // Session cookie secret (generate with openssl rand -base64 32)
	obot_encryption_key?: string & !=""         // Custom encryption key (generate with openssl rand -base64 32)
	obot_bootstrap_token?: string & !=""        // Initial admin bootstrap token
	obot_entra_tenant_id?: string & !=""        // Azure Entra ID tenant ID (GUID)
	obot_entra_client_id?: string & !=""        // Azure App Registration client ID (GUID)
	obot_entra_client_secret?: string & !=""    // Azure App Registration client secret
	obot_admin_emails?: string & !=""           // Comma-separated list of admin emails
	obot_owner_emails?: string & !=""           // Comma-separated list of owner emails
	obot_storage_size?: string & !=""           // Storage size for obot data (default: 20Gi)
	obot_storage_class?: string & !=""          // Storage class (default: proxmox-csi)
	obot_replicas?: int & >=1                   // Number of replicas (default: 1 for RWO storage)
	obot_cpu_request?: string & !=""            // CPU request (default: 500m)
	obot_cpu_limit?: string & !=""              // CPU limit (default: 2000m)
	obot_memory_request?: string & !=""         // Memory request (default: 1Gi)
	obot_memory_limit?: string & !=""           // Memory limit (default: 4Gi)
	obot_encryption_provider?: *"custom" | "azure-keyvault" | "aws-kms" | "gcp-kms"  // Encryption provider
	obot_use_ai_gateway?: *true | bool          // Use existing envoy-ai gateway for LLM requests
}

#Config
