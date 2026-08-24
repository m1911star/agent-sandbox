#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# omp-sandbox-down: Tear down OMP sandbox environment
# ─────────────────────────────────────────────────────────────────────────────

CONTAINER_NAME="omp-sandbox"
IMAGE_NAME="omp-sandbox:latest"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }

PURGE=false
[[ "${1:-}" == "--purge" ]] && PURGE=true

# ── Remove container ─────────────────────────────────────────────────────────
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    info "Container removed: $CONTAINER_NAME"
else
    warn "No container found: $CONTAINER_NAME"
fi

# ── Remove image (--purge only) ──────────────────────────────────────────────
if [[ "$PURGE" == true ]]; then
    if docker image inspect "$IMAGE_NAME" &>/dev/null; then
        docker rmi "$IMAGE_NAME" >/dev/null 2>&1
        info "Image removed: $IMAGE_NAME"
    fi
    docker image prune -f >/dev/null 2>&1
    info "Dangling images pruned"
else
    info "Image kept: $IMAGE_NAME (pass --purge to remove)"
fi

echo ""
info "Done. Host configuration was never touched."
