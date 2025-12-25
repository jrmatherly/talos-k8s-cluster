#!/usr/bin/env bash
# cleanup-failed-workflows.sh
# Bulk delete GitHub Actions workflow runs by status
#
# Usage:
#   ./scripts/cleanup-failed-workflows.sh [OPTIONS]
#
# Options:
#   --status STATUS Status to filter (default: failure)
#                   Valid: failure, cancelled, timed_out, skipped, stale, all
#   --limit N       Maximum number of runs to delete (default: 200)
#   --dry-run       Show what would be deleted without actually deleting
#   --workflow NAME Only delete runs from a specific workflow
#   --help          Show this help message
#
# Examples:
#   ./scripts/cleanup-failed-workflows.sh
#   ./scripts/cleanup-failed-workflows.sh --status cancelled
#   ./scripts/cleanup-failed-workflows.sh --status all --limit 50
#   ./scripts/cleanup-failed-workflows.sh --status failure --dry-run
#   ./scripts/cleanup-failed-workflows.sh --status timed_out --workflow "e2e.yaml"

set -Eeuo pipefail

# Default values
STATUS="failure"
LIMIT=200
DRY_RUN=false
WORKFLOW=""
REPO_OWNER="jrmatherly"
REPO_NAME="talos-k8s-cluster"

# Valid status values from GitHub API
VALID_STATUSES=("failure" "cancelled" "timed_out" "skipped" "stale" "all")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --status)
            STATUS="$2"
            shift 2
            ;;
        --limit)
            LIMIT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --workflow)
            WORKFLOW="$2"
            shift 2
            ;;
        --help)
            grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
done

# Validate status
if [[ ! " ${VALID_STATUSES[@]} " =~ " ${STATUS} " ]]; then
    echo -e "${RED}Error: Invalid status '${STATUS}'${NC}" >&2
    echo -e "Valid statuses: ${VALID_STATUSES[*]}" >&2
    exit 1
fi

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is not installed${NC}" >&2
    echo "Install it with: brew install gh" >&2
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo -e "${RED}Error: Not authenticated with GitHub${NC}" >&2
    echo "Run: gh auth login" >&2
    exit 1
fi

echo -e "${BLUE}=== GitHub Actions Workflow Cleanup ===${NC}"
echo -e "Repository: ${GREEN}${REPO_OWNER}/${REPO_NAME}${NC}"
echo -e "Status filter: ${GREEN}${STATUS}${NC}"
echo -e "Limit: ${GREEN}${LIMIT}${NC}"
echo -e "Dry run: ${GREEN}${DRY_RUN}${NC}"
if [[ -n "$WORKFLOW" ]]; then
    echo -e "Workflow: ${GREEN}${WORKFLOW}${NC}"
fi
echo ""

# Build the gh run list command based on status
if [[ "$STATUS" == "all" ]]; then
    # Fetch multiple statuses when 'all' is specified
    echo -e "${YELLOW}Fetching workflow runs with statuses: failure, cancelled, timed_out, skipped, stale...${NC}"
    WORKFLOW_RUNS=""
    for status in failure cancelled timed_out skipped stale; do
        echo -e "${YELLOW}  - Fetching ${status} runs...${NC}"
        RUNS=$(gh run list --repo "${REPO_OWNER}/${REPO_NAME}" --status "$status" --limit "${LIMIT}" --json databaseId,name,conclusion,status,createdAt --jq '.[]')
        if [[ -n "$RUNS" ]]; then
            if [[ -z "$WORKFLOW_RUNS" ]]; then
                WORKFLOW_RUNS="$RUNS"
            else
                WORKFLOW_RUNS="${WORKFLOW_RUNS}"$'\n'"${RUNS}"
            fi
        fi
    done
else
    # Single status filter
    echo -e "${YELLOW}Fetching workflow runs with status: ${STATUS}...${NC}"
    WORKFLOW_RUNS=$(gh run list --repo "${REPO_OWNER}/${REPO_NAME}" --status "${STATUS}" --limit "${LIMIT}" --json databaseId,name,conclusion,status,createdAt --jq '.[]')
fi

# Filter by workflow name if specified
if [[ -n "$WORKFLOW" ]]; then
    WORKFLOW_RUNS=$(echo "$WORKFLOW_RUNS" | jq -s ".[] | select(.name == \"${WORKFLOW}\")")
fi

if [[ -z "$WORKFLOW_RUNS" ]]; then
    echo -e "${GREEN}No workflow runs found matching the criteria!${NC}"
    exit 0
fi

# Count the runs
RUN_COUNT=$(echo "$WORKFLOW_RUNS" | jq -s 'length')
echo -e "${YELLOW}Found ${RUN_COUNT} workflow run(s)${NC}"
echo ""

# Show summary of what will be deleted
echo -e "${BLUE}Workflow runs to be deleted:${NC}"
echo "$WORKFLOW_RUNS" | jq -r '"  - \(.name) [\(.conclusion // .status)] (ID: \(.databaseId), Created: \(.createdAt))"'
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}DRY RUN: No workflows were deleted${NC}"
    echo -e "${YELLOW}Remove --dry-run flag to actually delete these runs${NC}"
    exit 0
fi

# Confirm deletion
read -p "$(echo -e ${YELLOW}Delete these ${RUN_COUNT} workflow runs? [y/N]: ${NC})" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cancelled${NC}"
    exit 0
fi

# Delete the runs
echo -e "${BLUE}Deleting workflow runs...${NC}"
DELETED=0
FAILED=0

echo "$WORKFLOW_RUNS" | jq -r '.databaseId' | while read -r RUN_ID; do
    if gh run delete "$RUN_ID" --repo "${REPO_OWNER}/${REPO_NAME}" 2>/dev/null; then
        ((DELETED++)) || true
        echo -e "${GREEN}✓${NC} Deleted run ID: $RUN_ID"
    else
        ((FAILED++)) || true
        echo -e "${RED}✗${NC} Failed to delete run ID: $RUN_ID"
    fi
done

echo ""
echo -e "${GREEN}=== Cleanup Complete ===${NC}"
echo -e "Successfully deleted: ${GREEN}${DELETED}${NC}"
if [[ $FAILED -gt 0 ]]; then
    echo -e "Failed to delete: ${RED}${FAILED}${NC}"
fi
