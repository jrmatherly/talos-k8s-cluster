import base64
import ipaddress
import json
import re
from pathlib import Path
from typing import Any

import makejinja


# Return the filename of a path without the j2 extension
def basename(value: str) -> str:
    return Path(value).stem


# Return the nth host in a CIDR range
def nthhost(value: str, query: int) -> str:
    try:
        network = ipaddress.ip_network(value, strict=False)
        if 0 <= query < network.num_addresses:
            return str(network[query])
    except ValueError:
        pass
    return False


# Return the age public or private key from age.key
def age_key(key_type: str, file_path: str = "age.key") -> str:
    try:
        with open(file_path, "r") as file:
            file_content = file.read().strip()
        if key_type == "public":
            key_match = re.search(r"# public key: (age1[\w]+)", file_content)
            if not key_match:
                raise ValueError("Could not find public key in the age key file.")
            return key_match.group(1)
        elif key_type == "private":
            key_match = re.search(r"(AGE-SECRET-KEY-[\w]+)", file_content)
            if not key_match:
                raise ValueError("Could not find private key in the age key file.")
            return key_match.group(1)
        else:
            raise ValueError("Invalid key type. Use 'public' or 'private'.")
    except FileNotFoundError:
        raise FileNotFoundError(f"File not found: {file_path}")
    except Exception as e:
        raise RuntimeError(f"Unexpected error while processing {file_path}: {e}")


# Return cloudflare tunnel fields from cloudflare-tunnel.json
def cloudflare_tunnel_id(file_path: str = "cloudflare-tunnel.json") -> str:
    try:
        with open(file_path, "r") as file:
            data = json.load(file)
        tunnel_id = data.get("TunnelID")
        if tunnel_id is None:
            raise KeyError(f"Missing 'TunnelID' key in {file_path}")
        return tunnel_id

    except FileNotFoundError:
        raise FileNotFoundError(f"File not found: {file_path}")
    except json.JSONDecodeError:
        raise ValueError(f"Could not decode JSON file: {file_path}")
    except KeyError as e:
        raise KeyError(f"Error in JSON structure: {e}")
    except Exception as e:
        raise RuntimeError(f"Unexpected error while processing {file_path}: {e}")


# Return cloudflare tunnel fields from cloudflare-tunnel.json in TUNNEL_TOKEN format
def cloudflare_tunnel_secret(file_path: str = "cloudflare-tunnel.json") -> str:
    try:
        with open(file_path, "r") as file:
            data = json.load(file)
        transformed_data = {
            "a": data["AccountTag"],
            "t": data["TunnelID"],
            "s": data["TunnelSecret"],
        }
        json_string = json.dumps(transformed_data, separators=(",", ":"))
        return base64.b64encode(json_string.encode("utf-8")).decode("utf-8")

    except FileNotFoundError:
        raise FileNotFoundError(f"File not found: {file_path}")
    except json.JSONDecodeError:
        raise ValueError(f"Could not decode JSON file: {file_path}")
    except KeyError as e:
        raise KeyError(f"Missing key in JSON file {file_path}: {e}")
    except Exception as e:
        raise RuntimeError(f"Unexpected error while processing {file_path}: {e}")


# Return the GitHub deploy key from github-deploy.key
def github_deploy_key(file_path: str = "github-deploy.key") -> str:
    try:
        with open(file_path, "r") as file:
            return file.read().strip()
    except FileNotFoundError:
        raise FileNotFoundError(f"File not found: {file_path}")
    except Exception as e:
        raise RuntimeError(f"Unexpected error while reading {file_path}: {e}")


# Return the Flux / GitHub push token from github-push-token.txt
def github_push_token(file_path: str = "github-push-token.txt") -> str:
    try:
        with open(file_path, "r") as file:
            return file.read().strip()
    except FileNotFoundError:
        raise FileNotFoundError(f"File not found: {file_path}")
    except Exception as e:
        raise RuntimeError(f"Unexpected error while reading {file_path}: {e}")


# Return a list of files in the talos patches directory
def talos_patches(value: str) -> list[str]:
    path = Path(f"templates/config/talos/patches/{value}")
    if not path.is_dir():
        return []
    return [str(f) for f in sorted(path.glob("*.yaml.j2")) if f.is_file()]


class Plugin(makejinja.plugin.Plugin):
    def __init__(self, data: dict[str, Any]):
        self._data = data

    def data(self) -> makejinja.plugin.Data:
        data = self._data

        # Handle multi-domain configuration with backward compatibility
        # Convert old cloudflare_domain (string) to new cloudflare_domains (array) format
        if "cloudflare_domain" in data and data["cloudflare_domain"]:
            if "cloudflare_domains" not in data or not data["cloudflare_domains"]:
                data["cloudflare_domains"] = [data["cloudflare_domain"]]

        # Ensure cloudflare_domains is a list
        domains = data.get("cloudflare_domains", [])
        if isinstance(domains, str):
            domains = [domains]
        data["cloudflare_domains"] = domains

        # Set primary_domain for convenience (first domain in list)
        data["primary_domain"] = domains[0] if domains else ""

        # Set default values for optional fields
        data.setdefault("node_default_gateway", nthhost(data.get("node_cidr"), 1))
        data.setdefault("node_dns_servers", ["1.1.1.1", "1.0.0.1"])

        # Set k8s_gateway fallback DNS (filter out private IPs to avoid DNS loops)
        # Only use public DNS servers from node_dns_servers, plus 1.1.1.1 as backup
        node_dns = data.get("node_dns_servers", ["1.1.1.1", "1.0.0.1"])
        fallback_dns = []
        for dns in node_dns:
            try:
                ip = ipaddress.ip_address(dns)
                # Only include public (non-private) IP addresses
                if not ip.is_private:
                    fallback_dns.append(dns)
            except ValueError:
                pass
        # Ensure we always have at least 1.1.1.1 as a fallback
        if "1.1.1.1" not in fallback_dns:
            fallback_dns.append("1.1.1.1")
        data.setdefault("k8s_gateway_fallback_dns", fallback_dns)
        data.setdefault("node_ntp_servers", ["162.159.200.1", "162.159.200.123"])
        data.setdefault("cluster_pod_cidr", "10.42.0.0/16")
        data.setdefault("cluster_svc_cidr", "10.43.0.0/16")
        data.setdefault("repository_branch", "main")
        data.setdefault("repository_visibility", "public")
        data.setdefault("cilium_loadbalancer_mode", "dsr")

        # If all BGP keys are set, enable BGP
        bgp_keys = [
            "cilium_bgp_router_addr",
            "cilium_bgp_router_asn",
            "cilium_bgp_node_asn",
        ]
        bgp_enabled = all(data.get(key) for key in bgp_keys)
        data.setdefault("cilium_bgp_enabled", bgp_enabled)

        # Control plane scheduling (allow workloads on control plane nodes)
        data.setdefault("allow_scheduling_on_control_planes", True)

        # If there is more than one node, enable spegel
        spegel_enabled = len(data.get("nodes")) > 1
        data.setdefault("spegel_enabled", spegel_enabled)

        # Proxmox CCM/CSI defaults
        data.setdefault("proxmox_insecure", True)
        data.setdefault("proxmox_region", "talos-k8s")
        data.setdefault("proxmox_storage", "local-lvm")

        # Envoy AI Gateway defaults
        data.setdefault("envoy_ai_gateway_enabled", False)
        # Azure OpenAI region defaults (empty strings to prevent undefined errors)
        data.setdefault("azure_openai_us_east_api_key", "")
        data.setdefault("azure_openai_us_east_resource_name", "")
        data.setdefault("azure_openai_us_east2_api_key", "")
        data.setdefault("azure_openai_us_east2_resource_name", "")
        # Azure Cohere Rerank API default
        data.setdefault("azure_cohere_rerank_api_key", "")
        data.setdefault("azure_cohere_rerank_api_base", "")
        # Azure Cohere Embed API default
        data.setdefault("azure_cohere_embed_api_key", "")
        data.setdefault("azure_cohere_embed_api_base", "")
        # Azure Anthropic API default
        data.setdefault("azure_anthropic_api_key", "")
        data.setdefault("azure_anthropic_api_base", "")

        # Observability Stack defaults (Prometheus/Grafana for K8s metrics)
        data.setdefault("observability_enabled", False)
        data.setdefault("grafana_admin_password", "admin")

        # Prometheus defaults
        data.setdefault("prometheus_retention", "7d")
        data.setdefault("prometheus_retention_size", "45GB")
        data.setdefault("prometheus_storage_size", "50Gi")
        data.setdefault("prometheus_storage_class", "proxmox-csi")
        data.setdefault("prometheus_replicas", 1)
        data.setdefault("prometheus_alertmanager_replicas", 1)
        data.setdefault("alertmanager_storage_size", "5Gi")
        data.setdefault("grafana_storage_size", "10Gi")

        # OneDev defaults (Git Server with CI/CD)
        data.setdefault("onedev_enabled", False)
        data.setdefault("onedev_admin_password", "")
        data.setdefault("onedev_storage_size", "100Gi")
        data.setdefault("onedev_storage_class", "proxmox-csi")
        data.setdefault("onedev_database_type", "")
        data.setdefault("onedev_database_host", "")
        data.setdefault("onedev_database_port", "3306")
        data.setdefault("onedev_database_name", "onedev")
        data.setdefault("onedev_database_user", "onedev")
        data.setdefault("onedev_database_password", "")
        data.setdefault("onedev_ssh_port", 6611)
        data.setdefault("onedev_cpu_limit", "2000m")
        data.setdefault("onedev_memory_limit", "4Gi")
        data.setdefault("onedev_cpu_request", "500m")
        data.setdefault("onedev_memory_request", "2Gi")

        # WorkOS AuthKit defaults (OAuth 2.1 / MCP authentication)
        data.setdefault("workos_client_id", "")
        data.setdefault("workos_client_secret", "")
        data.setdefault("workos_subdomain", "")

        # MCP Gateway defaults (Model Context Protocol)
        data.setdefault("mcp_gateway_enabled", False)
        data.setdefault("mcp_gateway_addr", "")
        data.setdefault("mcp_session_timeout", 3600)

        # Keycloak defaults (OIDC Authentication Provider)
        data.setdefault("keycloak_enabled", False)
        data.setdefault("keycloak_admin_password", "")
        data.setdefault("keycloak_db_password", "")
        data.setdefault("keycloak_replicas", 2)
        data.setdefault("keycloak_cpu_request", "250m")
        data.setdefault("keycloak_memory_request", "512Mi")
        data.setdefault("keycloak_cpu_limit", "1000m")
        data.setdefault("keycloak_memory_limit", "1Gi")
        data.setdefault("keycloak_postgresql_enabled", True)
        data.setdefault("keycloak_postgresql_replicas", 3)
        data.setdefault("keycloak_postgresql_storage_size", "10Gi")
        data.setdefault("keycloak_oidc_client_secret", "")
        data.setdefault("keycloak_oidc_cookie_domain", "")

        # Keycloak Entra ID Identity Provider defaults
        data.setdefault("keycloak_entra_id_enabled", False)
        data.setdefault("keycloak_entra_id_tenant_id", "")
        data.setdefault("keycloak_entra_id_client_id", "")
        data.setdefault("keycloak_entra_id_client_secret", "")

        # Keycloak Google Identity Provider defaults
        data.setdefault("keycloak_google_enabled", False)
        data.setdefault("keycloak_google_client_id", "")
        data.setdefault("keycloak_google_client_secret", "")

        # agentgateway defaults (MCP 2025-11-25 OAuth Proxy)
        data.setdefault("agentgateway_enabled", False)
        data.setdefault("agentgateway_addr", "")
        data.setdefault(
            "agentgateway_scopes", ["openid", "profile", "email", "offline_access"]
        )
        data.setdefault("keycloak_agentgateway_client_secret", "")

        # obot defaults (Multi-tenant MCP Gateway)
        data.setdefault("obot_enabled", False)
        data.setdefault("obot_hostname", "obot")
        data.setdefault("obot_entra_tenant_id", "")
        data.setdefault("obot_entra_client_id", "")
        data.setdefault("obot_entra_client_secret", "")
        # PostgreSQL configuration
        data.setdefault("obot_postgres_host", "")
        data.setdefault("obot_postgres_db", "obot")
        data.setdefault("obot_postgres_user", "obot")
        data.setdefault("obot_postgres_password", "")
        data.setdefault("obot_mcp_namespace", "obot-mcp")
        # Secrets
        data.setdefault("obot_cookie_secret", "")
        data.setdefault("obot_encryption_key", "")
        data.setdefault("obot_bootstrap_token", "")
        # User management
        data.setdefault("obot_admin_emails", "")
        data.setdefault("obot_owner_emails", "")
        # Storage
        data.setdefault("obot_storage_size", "20Gi")
        data.setdefault("obot_storage_class", "proxmox-csi")
        data.setdefault("obot_postgresql_replicas", 3)
        data.setdefault("obot_postgresql_storage_size", "10Gi")
        # Resources
        data.setdefault("obot_replicas", 1)
        data.setdefault("obot_cpu_request", "500m")
        data.setdefault("obot_cpu_limit", "2000m")
        data.setdefault("obot_memory_request", "1Gi")
        data.setdefault("obot_memory_limit", "4Gi")
        # Advanced
        data.setdefault("obot_encryption_provider", "custom")
        data.setdefault("obot_use_ai_gateway", True)
        data.setdefault("obot_use_agentgateway", False)
        # S3/MinIO Workspace Storage (enables multi-replica scaling)
        data.setdefault("obot_workspace_provider", "directory")
        data.setdefault("obot_s3_bucket", "")
        data.setdefault("obot_s3_endpoint", "")
        data.setdefault("obot_s3_region", "us-east-1")
        data.setdefault("obot_s3_access_key", "")
        data.setdefault("obot_s3_secret_key", "")
        data.setdefault("obot_s3_use_path_style", False)

        # MinIO defaults (S3-compatible object storage in storage namespace)
        data.setdefault("minio_enabled", False)
        data.setdefault("minio_chart_version", "5.4.0")
        data.setdefault("minio_mode", "standalone")
        data.setdefault("minio_replicas", 1)
        data.setdefault("minio_root_user", "admin")
        data.setdefault("minio_root_password", "")
        data.setdefault("minio_storage_class", "proxmox-csi")
        data.setdefault("minio_storage_size", "50Gi")
        data.setdefault("minio_memory_request", "512Mi")
        data.setdefault("minio_memory_limit", "2Gi")
        data.setdefault("minio_cpu_request", "250m")
        data.setdefault("minio_ingress_enabled", False)
        data.setdefault("minio_console_hostname", "minio")
        data.setdefault("minio_buckets", [])
        data.setdefault("minio_users", [])

        # Compute proxmox_csi_enabled for dependency checking
        proxmox_csi_enabled = bool(
            data.get("proxmox_csi_token_id") and data.get("proxmox_csi_token_secret")
        )
        data.setdefault("proxmox_csi_enabled", proxmox_csi_enabled)

        # kagent defaults (Kubernetes-native AI Agent Framework)
        data.setdefault("kagent_enabled", False)
        data.setdefault("kagent_provider", "anthropic")
        data.setdefault("kagent_default_model", "claude-3-5-haiku")
        data.setdefault("kagent_anthropic_api_key", "")
        data.setdefault("kagent_openai_api_key", "")
        data.setdefault("kagent_openai_api_base", "")
        data.setdefault("kagent_gemini_api_key", "")
        data.setdefault("kagent_azure_endpoint", "")
        data.setdefault("kagent_azure_deployment", "")
        data.setdefault("kagent_ollama_host", "ollama.ollama.svc.cluster.local:11434")
        data.setdefault("kagent_ui_enabled", True)
        data.setdefault("kagent_ui_replicas", 1)
        data.setdefault("kagent_controller_replicas", 1)
        data.setdefault("kagent_controller_log_level", "info")
        data.setdefault("kagent_agents_enabled", ["k8s", "helm", "observability"])
        data.setdefault("kagent_otlp_enabled", False)
        data.setdefault("kagent_otlp_endpoint", "")
        data.setdefault("kagent_database_type", "sqlite")
        data.setdefault("kagent_postgres_url", "")
        data.setdefault("kagent_kmcp_enabled", True)
        data.setdefault("kagent_write_operations_enabled", False)
        # kagent Grafana MCP settings (uses existing cluster Grafana)
        data.setdefault(
            "kagent_grafana_url",
            "http://kube-prometheus-stack-grafana.observability.svc:80/api",
        )
        data.setdefault("kagent_grafana_api_key", "")
        # kagent CloudNativePG (CNPG) PostgreSQL settings
        data.setdefault("kagent_postgresql_replicas", 3)
        data.setdefault("kagent_postgresql_storage_size", "10Gi")
        data.setdefault("kagent_postgres_user", "kagent")
        data.setdefault("kagent_postgres_password", "")

        # LiteLLM defaults (LLM Proxy with Multi-Provider Routing)
        data.setdefault("litellm_enabled", False)
        data.setdefault("litellm_master_key", "")
        data.setdefault("litellm_salt_key", "")
        data.setdefault("litellm_db_password", "")
        data.setdefault("litellm_cache_password", "")
        data.setdefault("litellm_database_url", "")
        data.setdefault("litellm_redis_url", "")
        data.setdefault("litellm_mcp_enabled", True)
        data.setdefault("litellm_replicas_min", 2)
        data.setdefault("litellm_replicas_max", 5)
        data.setdefault("litellm_cpu_request", "500m")
        data.setdefault("litellm_cpu_limit", "2000m")
        data.setdefault("litellm_memory_request", "512Mi")
        data.setdefault("litellm_memory_limit", "2Gi")
        data.setdefault("litellm_postgresql_replicas", 3)
        data.setdefault("litellm_postgresql_storage_size", "20Gi")
        data.setdefault("litellm_cache_memory", "1Gi")
        data.setdefault("litellm_langfuse_enabled", False)
        data.setdefault("litellm_langfuse_host", "https://cloud.langfuse.com")
        data.setdefault("litellm_langfuse_public_key", "")
        data.setdefault("litellm_langfuse_secret_key", "")

        # Cognee Graph RAG defaults
        data.setdefault("cognee_enabled", False)
        data.setdefault("cognee_dedicated_db", True)
        data.setdefault("cognee_db_name", "cognee")
        data.setdefault("cognee_db_password", "")
        data.setdefault("cognee_neo4j_password", "")
        data.setdefault("cognee_neo4j_version", "5.26.0")
        data.setdefault("cognee_neo4j_storage_size", "10Gi")
        primary_domain = data.get("primary_domain", "example.com")
        data.setdefault("cognee_llm_base_url", f"https://llms.{primary_domain}/v1")
        data.setdefault("cognee_embedding_model", "text-embedding-3-large")
        data.setdefault("cognee_embedding_dimensions", 3072)
        data.setdefault("cognee_mcp_server_name", "cognee-mcp")
        # Cognee API Server defaults
        data.setdefault("cognee_api_enabled", False)
        data.setdefault("cognee_version", "0.5.0")
        data.setdefault("cognee_replicas", 1)
        data.setdefault("cognee_api_resources_requests_cpu", "100m")
        data.setdefault("cognee_api_resources_requests_memory", "512Mi")
        data.setdefault("cognee_api_resources_limits_cpu", "2000m")
        data.setdefault("cognee_api_resources_limits_memory", "4Gi")

        return data

    def filters(self) -> makejinja.plugin.Filters:
        return [basename, nthhost]

    def functions(self) -> makejinja.plugin.Functions:
        return [
            age_key,
            cloudflare_tunnel_id,
            cloudflare_tunnel_secret,
            github_deploy_key,
            github_push_token,
            talos_patches,
        ]
