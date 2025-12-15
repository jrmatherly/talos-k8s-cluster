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
	allow_scheduling_on_control_planes?: *false | bool  // Allow workloads on control plane nodes

	// Proxmox CSI Integration (required for Proxmox storage)
	proxmox_api_url?: string & =~"^https?://.+/api2/json$"
	proxmox_insecure?: *false | bool
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

	// Azure Cohere Rerank API (optional - for reranking models)
	azure_cohere_rerank_api_key?: string & !=""
	azure_cohere_rerank_api_base?: string & !=""

	// Azure Cohere Embed API (optional - for embedding models)
	azure_cohere_embed_api_key?: string & !=""
	azure_cohere_embed_api_base?: string & !=""

	// Azure Anthropic API (optional - for Claude models via Azure AI)
	azure_anthropic_api_key?: string & !=""
	azure_anthropic_api_base?: string & !=""

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

	// Keycloak Google Identity Provider (optional - federation with Google)
	keycloak_google_enabled?: bool               // Enable Google as identity provider
	keycloak_google_client_id?: string & !=""    // Google OAuth client ID
	keycloak_google_client_secret?: string & !="" // Google OAuth client secret

	// agentgateway Configuration (MCP 2025-11-25 OAuth Proxy)
	// Wraps Keycloak for MCP spec-compliant authentication (DCR, CIMD, Protected Resource Metadata)
	agentgateway_enabled?: bool                 // Enable agentgateway for MCP authentication
	agentgateway_addr?: net.IPv4 & !=cluster_api_addr & !=cluster_gateway_addr & !=cluster_dns_gateway_addr & !=cloudflare_gateway_addr & !=envoy_ai_gateway_addr & !=mcp_gateway_addr
	agentgateway_scopes?: [...string]           // OAuth scopes (default: openid, profile, email, offline_access)
	keycloak_agentgateway_client_secret?: string & !="" // Client secret for agentgateway (defaults to keycloak_oidc_client_secret)

	// obot Configuration (Multi-tenant MCP Gateway)
	// Self-hosted AI agent platform with Entra ID authentication
	obot_enabled?: bool                         // Enable obot MCP gateway
	obot_hostname?: string & !=""               // Hostname subdomain (default: obot)
	obot_entra_tenant_id?: string & !=""        // Azure Entra ID tenant ID (GUID)
	obot_entra_client_id?: string & !=""        // Azure App Registration client ID (GUID)
	obot_entra_client_secret?: string & !=""    // Azure App Registration client secret
	obot_postgres_host?: string                 // PostgreSQL host (empty for CloudNativePG)
	obot_postgres_db?: string & !=""            // PostgreSQL database name (default: obot)
	obot_postgres_user?: string & !=""          // PostgreSQL username (default: obot)
	obot_postgres_password?: string & !=""      // PostgreSQL password for obot database
	obot_mcp_namespace?: string & !=""          // Namespace for MCP servers (default: obot-mcp)
	obot_cookie_secret?: string & !=""          // Session cookie secret (generate with openssl rand -base64 32)
	obot_encryption_key?: string & !=""         // Custom encryption key (generate with openssl rand -base64 32)
	obot_bootstrap_token?: string & !=""        // Initial admin bootstrap token
	obot_admin_emails?: string & !=""           // Comma-separated list of admin emails
	obot_owner_emails?: string & !=""           // Comma-separated list of owner emails
	obot_storage_size?: string & !=""           // Storage size for obot data (default: 20Gi)
	obot_storage_class?: string & !=""          // Storage class (default: proxmox-csi)
	obot_postgresql_replicas?: int & >=1        // PostgreSQL replicas (default: 3)
	obot_postgresql_storage_size?: string & !="" // PostgreSQL storage size (default: 10Gi)
	obot_replicas?: int & >=1                   // Number of replicas (default: 1 for RWO storage)
	obot_cpu_request?: string & !=""            // CPU request (default: 500m)
	obot_cpu_limit?: string & !=""              // CPU limit (default: 2000m)
	obot_memory_request?: string & !=""         // Memory request (default: 1Gi)
	obot_memory_limit?: string & !=""           // Memory limit (default: 4Gi)
	obot_encryption_provider?: *"custom" | "azure-keyvault" | "aws-kms" | "gcp-kms"  // Encryption provider
	obot_use_ai_gateway?: *false | bool          // Use existing envoy-ai gateway for LLM requests
	obot_use_agentgateway?: *false | bool       // Use agentgateway (ai-gw) instead of envoy-ai (llms) for LLM requests

	// obot S3/MinIO Workspace Storage (enables multi-replica scaling)
	obot_workspace_provider?: *"directory" | "s3" | "azure"  // Workspace storage backend (default: directory)
	obot_s3_bucket?: string & !=""              // S3 bucket name for workspace storage
	obot_s3_endpoint?: string & !=""            // S3-compatible endpoint (e.g., http://minio.storage.svc.cluster.local:9000)
	obot_s3_region?: string & !=""              // S3 region (default: us-east-1)
	obot_s3_access_key?: string & !=""          // S3 access key (MinIO access key)
	obot_s3_secret_key?: string & !=""          // S3 secret key (MinIO secret key)
	obot_s3_use_path_style?: bool               // Use path-style URLs (required for MinIO without wildcard DNS)

	// MinIO Configuration (S3-compatible object storage)
	// Shared storage namespace for S3-compatible object storage used by obot and other services
	minio_enabled?: bool                        // Enable MinIO deployment
	minio_chart_version?: string & !=""         // MinIO Helm chart version
	minio_mode?: *"standalone" | "distributed"  // Deployment mode (standalone for single node, distributed for HA)
	minio_replicas?: int & >=1                  // Number of replicas (4+ required for distributed mode)
	minio_root_user?: string & !=""             // MinIO root username (admin account)
	minio_root_password?: string & !=""         // MinIO root password (admin account) - will be encrypted with SOPS
	minio_storage_class?: string & !=""         // Storage class for PVC (default: proxmox-csi)
	minio_storage_size?: string & !=""          // Storage size for each replica (default: 50Gi)
	minio_memory_request?: string & !=""        // Memory request (default: 512Mi)
	minio_memory_limit?: string & !=""          // Memory limit (default: 2Gi)
	minio_cpu_request?: string & !=""           // CPU request (default: 250m)
	minio_ingress_enabled?: bool                // Enable console HTTPRoute via Envoy Gateway
	minio_console_hostname?: string & !=""      // Console hostname subdomain (default: minio)
	minio_buckets?: [...{                       // List of buckets to create
		name: string & !=""                       // Bucket name
		policy?: *"none" | "public" | "download" | "upload"  // Bucket policy
	}]
	minio_users?: [...{                         // List of service account users
		access_key: string & !=""                 // User access key
		secret_key: string & !=""                 // User secret key
		policy?: *"readwrite" | "readonly" | "writeonly" | "consoleAdmin"  // User policy
	}]

	// kagent Configuration (Kubernetes-native AI Agent Framework)
	// Cloud Native Computing Foundation (CNCF) sandbox project for AI agents
	kagent_enabled?: bool                       // Enable kagent deployment
	kagent_provider?: *"anthropic" | "openai" | "azure" | "gemini" | "ollama"  // LLM provider
	kagent_default_model?: string & !=""        // Default model name (e.g., claude-3-5-haiku, gpt-4o)
	kagent_anthropic_api_key?: string & !=""    // Anthropic API key (if provider=anthropic)
	kagent_openai_api_key?: string & !=""       // OpenAI API key (if provider=openai)
	kagent_openai_api_base?: string & !=""      // OpenAI-compatible API base URL (for AI Gateway routing)
	kagent_ui_enabled?: *false | bool            // Enable kagent web UI
	kagent_ui_replicas?: int & >=1              // Number of UI replicas (default: 1)
	kagent_controller_replicas?: int & >=1      // Number of controller replicas (default: 1)
	kagent_controller_log_level?: *"info" | "debug" | "warn" | "error"  // Controller log level
	kagent_agents_enabled?: [...string]         // List of pre-built agents to enable (e.g., k8s, helm, observability)
	kagent_otlp_enabled?: bool                  // Enable OpenTelemetry tracing
	kagent_otlp_endpoint?: string & !=""        // OTLP endpoint (e.g., jaeger-collector.jaeger.svc:4317)
	kagent_database_type?: *"sqlite" | "postgres"  // Database type (sqlite or postgres)
	kagent_postgres_url?: string & !=""         // PostgreSQL connection URL (if database_type=postgres) - DEPRECATED, use CNPG
	kagent_postgres_user?: string & !=""        // PostgreSQL user (if database_type=postgres, CNPG bootstrap)
	kagent_postgres_password?: string & !=""    // PostgreSQL password (if database_type=postgres, CNPG bootstrap)
	kagent_postgresql_replicas?: int & >=1      // CNPG PostgreSQL replicas (default: 3)
	kagent_postgresql_storage_size?: string & !=""  // CNPG PostgreSQL storage size (default: 10Gi)
	kagent_kmcp_enabled?: *false | bool          // Enable kmcp MCP server controller
	kagent_write_operations_enabled?: bool      // Enable write operations for k8s-agent (default: false for safety)
	kagent_grafana_url?: string & !=""          // Grafana URL for grafana-mcp tool (default: cluster Grafana)
	kagent_grafana_api_key?: string & !=""      // Grafana API key for grafana-mcp tool (optional)
	kagent_gemini_api_key?: string & !=""       // Google Gemini API key (if provider=gemini)
	kagent_azure_endpoint?: string & !=""       // Azure OpenAI endpoint (if provider=azure)
	kagent_azure_deployment?: string & !=""     // Azure OpenAI deployment name (if provider=azure)
	kagent_ollama_host?: string & !=""          // Ollama host (if provider=ollama, default: ollama.ollama.svc.cluster.local:11434)

	// LiteLLM Configuration (LLM Proxy with Multi-Provider Routing)
	// Unified AI Gateway for routing requests across Azure OpenAI, Anthropic, and other providers
	litellm_enabled?: bool                      // Enable LiteLLM deployment
	litellm_master_key?: string & !=""          // Master key for admin API access (generate with: openssl rand -hex 32)
	litellm_salt_key?: string & !=""            // Salt key for encrypting API keys in database (DO NOT change after adding models)
	litellm_db_password?: string & !=""         // PostgreSQL password for LiteLLM database
	litellm_cache_password?: string & !=""      // Dragonfly/Redis password for caching
	litellm_database_url?: string & !=""        // PostgreSQL connection URL (optional - auto-generated if not set)
	litellm_redis_url?: string & !=""           // Redis/Dragonfly connection URL (optional - auto-generated if not set)
	litellm_mcp_enabled?: *false | bool          // Enable MCP server support (Open Source feature)
	litellm_replicas_min?: int & >=1            // Minimum replicas for HPA (default: 2)
	litellm_replicas_max?: int & >=1            // Maximum replicas for HPA (default: 5)
	litellm_cpu_request?: string & !=""         // CPU request (default: 500m)
	litellm_cpu_limit?: string & !=""           // CPU limit (default: 2000m)
	litellm_memory_request?: string & !=""      // Memory request (default: 512Mi)
	litellm_memory_limit?: string & !=""        // Memory limit (default: 2Gi)
	litellm_postgresql_replicas?: int & >=1     // CNPG PostgreSQL replicas (default: 3)
	litellm_postgresql_storage_size?: string & !=""  // CNPG PostgreSQL storage size (default: 20Gi)
	litellm_cache_memory?: string & !=""        // Dragonfly memory limit (default: 1Gi)
	litellm_langfuse_enabled?: bool             // Enable Langfuse observability integration
	litellm_langfuse_host?: string & !=""       // Langfuse host URL (default: https://cloud.langfuse.com)
	litellm_langfuse_public_key?: string & !="" // Langfuse public key
	litellm_langfuse_secret_key?: string & !="" // Langfuse secret key

	// Cognee Graph RAG Configuration (optional - requires obot_enabled)
	// Graph RAG capabilities using Neo4j for graph storage and pgvector for vector embeddings
	cognee_enabled?: bool                       // Enable Cognee Graph RAG integration
	cognee_dedicated_db?: bool                  // Use dedicated CNPG cluster (vs extending obot-db)
	cognee_db_name?: string & !=""              // Database name (default: cognee)
	cognee_db_password?: string & !=""          // PostgreSQL password for Cognee database
	cognee_neo4j_password?: string & !=""       // Neo4j password (required if cognee_enabled)
	cognee_neo4j_version?: string & !=""        // Neo4j CE version (default: 5.26.0)
	cognee_neo4j_storage_size?: string & !=""   // Neo4j PVC size (default: 10Gi)
	cognee_llm_base_url?: string & !=""         // LLM endpoint (default: https://llms.${SECRET_DOMAIN}/v1)
	cognee_llm_model?: string & !=""            // LLM model name (default: gpt-4o-mini)
	cognee_embedding_model?: string & !=""      // Embedding model name (default: text-embedding-3-large)
	cognee_embedding_dimensions?: int & >=1    // Embedding dimensions (default: 3072)
	cognee_mcp_server_name?: string & !=""     // MCP server name for NetworkPolicy selectors (default: cognee-mcp)

	// Cognee API Server Configuration (optional - requires cognee_enabled)
	cognee_api_enabled?: bool                   // Enable Cognee API server deployment with UI
	cognee_hostname?: string & !=""             // Hostname subdomain (default: cognee)
	cognee_version?: string & !=""              // Cognee Docker image version (default: 0.5.0)
	cognee_replicas?: int & >=1                 // Number of Cognee API replicas (default: 1)
	cognee_api_resources_requests_cpu?: string & !=""     // CPU request (default: 100m)
	cognee_api_resources_requests_memory?: string & !=""  // Memory request (default: 512Mi)
	cognee_api_resources_limits_cpu?: string & !=""       // CPU limit (default: 2000m)
	cognee_api_resources_limits_memory?: string & !=""    // Memory limit (default: 4Gi)
}

#Config
