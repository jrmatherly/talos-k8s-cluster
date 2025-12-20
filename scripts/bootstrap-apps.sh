#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

export LOG_LEVEL="debug"
export ROOT_DIR="$(git rev-parse --show-toplevel)"

# Talos requires the nodes to be 'Ready=False' before applying resources
function wait_for_nodes() {
    log debug "Waiting for nodes to be available"

    # Skip waiting if all nodes are 'Ready=True'
    if kubectl wait nodes --for=condition=Ready=True --all --timeout=10s &>/dev/null; then
        log info "Nodes are available and ready, skipping wait for nodes"
        return
    fi

    # Wait for all nodes to be 'Ready=False'
    until kubectl wait nodes --for=condition=Ready=False --all --timeout=10s &>/dev/null; do
        log info "Nodes are not available, waiting for nodes to be available. Retrying in 10 seconds..."
        sleep 10
    done
}

# Namespaces to be applied before the SOPS secrets are installed
function apply_namespaces() {
    log debug "Applying namespaces"

    local -r apps_dir="${ROOT_DIR}/kubernetes/apps"

    if [[ ! -d "${apps_dir}" ]]; then
        log error "Directory does not exist" "directory=${apps_dir}"
    fi

    for app in "${apps_dir}"/*/; do
        namespace=$(basename "${app}")

        # Check if the namespace resources are up-to-date
        if kubectl get namespace "${namespace}" &>/dev/null; then
            log info "Namespace resource is up-to-date" "resource=${namespace}"
            continue
        fi

        # Apply the namespace resources
        if kubectl create namespace "${namespace}" --dry-run=client --output=yaml \
            | kubectl apply --server-side --filename - &>/dev/null;
        then
            log info "Namespace resource applied" "resource=${namespace}"
        else
            log error "Failed to apply namespace resource" "resource=${namespace}"
        fi
    done
}

# SOPS secrets to be applied before the helmfile charts are installed
function apply_sops_secrets() {
    log debug "Applying secrets"

    local -r secrets=(
        "${ROOT_DIR}/bootstrap/github-deploy-key.sops.yaml"
        "${ROOT_DIR}/bootstrap/sops-age.sops.yaml"
        "${ROOT_DIR}/kubernetes/components/sops/cluster-secrets.sops.yaml"
    )

    for secret in "${secrets[@]}"; do
        if [ ! -f "${secret}" ]; then
            log warn "File does not exist" "file=${secret}"
            continue
        fi

        # Check if the secret resources are up-to-date
        if sops exec-file "${secret}" "kubectl --namespace flux-system diff --filename {}" &>/dev/null; then
            log info "Secret resource is up-to-date" "resource=$(basename "${secret}" ".sops.yaml")"
            continue
        fi

        # Apply secret resources
        if sops exec-file "${secret}" "kubectl --namespace flux-system apply --server-side --filename {}" &>/dev/null; then
            log info "Secret resource applied successfully" "resource=$(basename "${secret}" ".sops.yaml")"
        else
            log error "Failed to apply secret resource" "resource=$(basename "${secret}" ".sops.yaml")"
        fi
    done
}

# Gateway API CRDs from kubernetes-sigs (required for kgateway/agentgateway)
function apply_gateway_api_crds() {
    log debug "Checking Gateway API CRD requirements"

    local -r cluster_config="${ROOT_DIR}/cluster.yaml"

    if [[ ! -f "${cluster_config}" ]]; then
        log warn "cluster.yaml not found, skipping Gateway API CRDs"
        return
    fi

    # Check if kgateway or agentgateway is enabled (kgateway defaults to true)
    local kgateway_enabled agentgateway_enabled
    kgateway_enabled=$(yq '.kgateway_enabled // true' "${cluster_config}")
    agentgateway_enabled=$(yq '.agentgateway_enabled // false' "${cluster_config}")

    if [[ "${kgateway_enabled}" != "true" && "${agentgateway_enabled}" != "true" ]]; then
        log info "Neither kgateway nor agentgateway enabled, skipping Gateway API CRDs"
        return
    fi

    # Get Gateway API version from cluster.yaml (default: v1.4.1)
    local gateway_api_version
    gateway_api_version=$(yq '.gateway_api_version // "v1.4.1"' "${cluster_config}")

    log info "Installing kubernetes-sigs Gateway API CRDs" "version=${gateway_api_version}"

    local -r gateway_api_url="https://github.com/kubernetes-sigs/gateway-api/releases/download/${gateway_api_version}/experimental-install.yaml"

    # Check if CRDs are up-to-date
    if kubectl diff --filename "${gateway_api_url}" &>/dev/null; then
        log info "Gateway API CRDs are up-to-date"
        return
    fi

    # Apply Gateway API CRDs
    if ! kubectl apply --server-side --filename "${gateway_api_url}" &>/dev/null; then
        log fatal "Failed to apply Gateway API CRDs" "url=${gateway_api_url}"
    fi

    log info "Gateway API CRDs applied successfully" "version=${gateway_api_version}"
}

# CRDs to be applied before the helmfile charts are installed
function apply_crds() {
    log debug "Applying CRDs"

    local -r helmfile_file="${ROOT_DIR}/bootstrap/helmfile.d/00-crds.yaml"

    if [[ ! -f "${helmfile_file}" ]]; then
        log fatal "File does not exist" "file" "${helmfile_file}"
    fi

    if ! crds=$(helmfile --file "${helmfile_file}" template --quiet) || [[ -z "${crds}" ]]; then
        log fatal "Failed to render CRDs from Helmfile" "file" "${helmfile_file}"
    fi

    if echo "${crds}" | kubectl diff --filename - &>/dev/null; then
        log info "CRDs are up-to-date"
        return
    fi

    if ! echo "${crds}" | kubectl apply --server-side --filename - &>/dev/null; then
        log fatal "Failed to apply crds from Helmfile" "file" "${helmfile_file}"
    fi

    log info "CRDs applied successfully"
}

# Sync Helm releases
function sync_helm_releases() {
    log debug "Syncing Helm releases"

    local -r helmfile_file="${ROOT_DIR}/bootstrap/helmfile.d/01-apps.yaml"

    if [[ ! -f "${helmfile_file}" ]]; then
        log error "File does not exist" "file=${helmfile_file}"
    fi

    if ! helmfile --file "${helmfile_file}" sync --hide-notes; then
        log error "Failed to sync Helm releases"
    fi

    log info "Helm releases synced successfully"
}

function main() {
    check_env KUBECONFIG TALOSCONFIG
    check_cli helmfile kubectl kustomize sops talhelper yq

    # Apply resources and Helm releases
    wait_for_nodes
    apply_namespaces
    apply_sops_secrets
    apply_gateway_api_crds  # kubernetes-sigs Gateway API CRDs (before helmfile CRDs)
    apply_crds              # Helm chart CRDs (kgateway-crds, etc.)
    sync_helm_releases

    log info "Congrats! The cluster is bootstrapped and Flux is syncing the Git repository"
}

main "$@"
