#!/usr/bin/env bash
set -Eeuo pipefail

# etcd Backup Script for Talos Kubernetes Cluster
# Creates a snapshot of etcd and stores it locally
# REF: https://docs.siderolabs.com/talos/v1.11/build-and-extend-talos/cluster-operations-and-maintenance/etcd-maintenance

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

# Check required tools
check_cli talosctl

# Configuration
CONTROL_PLANE_IP="${1:-192.168.22.101}"
BACKUP_DIR="${BACKUP_DIR:-./backups/etcd}"
BACKUP_NAME="etcd-$(date +%Y%m%d-%H%M%S).db"
KEEP_BACKUPS="${KEEP_BACKUPS:-7}"

# Create backup directory
mkdir -p "${BACKUP_DIR}"

log info "Creating etcd snapshot from control plane node" "node=${CONTROL_PLANE_IP}"

# Create snapshot on the node
talosctl -n "${CONTROL_PLANE_IP}" etcd snapshot "${BACKUP_NAME}"

log info "Copying snapshot to local backup directory" "path=${BACKUP_DIR}/${BACKUP_NAME}"

# Copy snapshot to local machine
talosctl -n "${CONTROL_PLANE_IP}" copy "/var/${BACKUP_NAME}" "${BACKUP_DIR}/"

# Verify the backup exists
if [[ -f "${BACKUP_DIR}/${BACKUP_NAME}" ]]; then
    BACKUP_SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_NAME}" | cut -f1)
    log info "Backup completed successfully" "file=${BACKUP_NAME}" "size=${BACKUP_SIZE}"
else
    log error "Backup file not found" "path=${BACKUP_DIR}/${BACKUP_NAME}"
fi

# Cleanup old backups (keep last N)
log info "Cleaning up old backups" "keep=${KEEP_BACKUPS}"
cd "${BACKUP_DIR}"
# shellcheck disable=SC2012
ls -t ./*.db 2>/dev/null | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm -f

# List remaining backups
BACKUP_COUNT=$(find . -name "*.db" -type f 2>/dev/null | wc -l | tr -d ' ')
log info "Backup rotation complete" "total_backups=${BACKUP_COUNT}"