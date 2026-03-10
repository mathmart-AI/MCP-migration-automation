#!/usr/bin/env bash
# ==============================================================================
# 🚀 MCP Axon Environment — Plug & Play Startup Script
# Architecture: Go Proxy (Copilot SDK) → Python Backend (Docker)
# Run from: mcp-axon-proxy/ root, e.g.  ./scripts/start_mcp_environment.sh
# ==============================================================================
set -euo pipefail

# ── Root of the project (parent of scripts/) ──────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Configuration ─────────────────────────────────────────────────────────────
AXON_IMAGE_NAME="axon-mcp-backend"
AXON_CONTAINER_NAME="axon-mcp-backend"
AXON_PORT=8000
AXON_BACKEND_DIR="${PROJECT_ROOT}/../Axon.MCP.Server"
GO_BINARY="${PROJECT_ROOT}/mcp-axon-proxy"
MAX_WAIT_SECONDS=30

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[✓]${NC}     $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[✗]${NC}     $*"; }

# ── Cleanup on exit ──────────────────────────────────────────────────────────
cleanup() {
    log_warn "Shutting down..."
    if docker ps -q --filter "name=${AXON_CONTAINER_NAME}" 2>/dev/null | grep -q .; then
        docker stop "${AXON_CONTAINER_NAME}" >/dev/null 2>&1 || true
        docker rm "${AXON_CONTAINER_NAME}" >/dev/null 2>&1 || true
        log_ok "Docker container stopped."
    fi
}
trap cleanup EXIT INT TERM

# ==============================================================================
# STEP 0: Check prerequisites
# ==============================================================================
log_info "Checking prerequisites..."

if ! command -v go &>/dev/null; then
    log_error "Go is not installed. Install Go >= 1.21 from https://go.dev/dl/"
    exit 1
fi
log_ok "Go found: $(go version)"

if ! command -v docker &>/dev/null; then
    log_error "Docker is not installed. Install Docker Desktop from https://www.docker.com/products/docker-desktop/"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &>/dev/null; then
    log_error "Docker daemon is not running. Start Docker Desktop first."
    exit 1
fi
log_ok "Docker is running."

# ==============================================================================
# STEP 1: Compile the Go Proxy binary
# ==============================================================================
log_info "Compiling Go proxy binary..."
(cd "${PROJECT_ROOT}" && go build -o "${GO_BINARY}" ./cmd/server)
log_ok "Go binary compiled: ${GO_BINARY}"

# ==============================================================================
# STEP 2: Build & Start the Python backend Docker container
# ==============================================================================

# Stop any existing container
if docker ps -aq --filter "name=${AXON_CONTAINER_NAME}" 2>/dev/null | grep -q .; then
    log_warn "Removing existing container '${AXON_CONTAINER_NAME}'..."
    docker stop "${AXON_CONTAINER_NAME}" >/dev/null 2>&1 || true
    docker rm "${AXON_CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

# Build the Docker image
log_info "Building Docker image '${AXON_IMAGE_NAME}'..."
if [ ! -d "${AXON_BACKEND_DIR}" ]; then
    log_error "Axon backend directory not found at '${AXON_BACKEND_DIR}'."
    log_error "Expected: ${AXON_BACKEND_DIR}"
    exit 1
fi

docker build -t "${AXON_IMAGE_NAME}" "${AXON_BACKEND_DIR}"
log_ok "Docker image built successfully."

# ── Workspace volume (optional) ──────────────────────────────────────────────
# Mount /WORKSPACE only when AXON_WORKSPACE is explicitly set by the caller.
# If unset, /WORKSPACE is not mounted (use axon-start.sh for auto-workspace).
WORKSPACE_MOUNT_ARGS=()
if [ -n "${AXON_WORKSPACE:-}" ] && [ -d "${AXON_WORKSPACE}" ]; then
    WORKSPACE_MOUNT_ARGS=(-v "${AXON_WORKSPACE}:/WORKSPACE")
    log_info "Mounting ${AXON_WORKSPACE} → /WORKSPACE (workspace folder)"
fi

# Start the container (with volume mount for local file analysis)
log_info "Starting Python backend on port ${AXON_PORT}..."
log_info "Mounting ${HOME}/CONTEXT → /CONTEXT (for Tree-sitter analysis)"
docker run -d \
    --name "${AXON_CONTAINER_NAME}" \
    -p "${AXON_PORT}:${AXON_PORT}" \
    -v "${HOME}/CONTEXT:/CONTEXT" \
    "${WORKSPACE_MOUNT_ARGS[@]}" \
    -e AUTH_ENABLED=false \
    -e MCP_AUTH_ENABLED=false \
    -e MCP_TRANSPORT=http \
    -e MCP_HTTP_HOST=0.0.0.0 \
    -e MCP_HTTP_PORT="${AXON_PORT}" \
    -e API_HOST=0.0.0.0 \
    -e API_PORT="${AXON_PORT}" \
    -e DATABASE_URL=sqlite+aiosqlite:// \
    -e JWT_SECRET_KEY=local-dev-secret-key-min-64-characters-for-local-development-only-not-production \
    -e REDIS_CACHE_ENABLED=false \
    -e LOG_LEVEL=INFO \
    -e ENVIRONMENT=local \
    -e DEBUG=false \
    "${AXON_IMAGE_NAME}"
if [ ${#WORKSPACE_MOUNT_ARGS[@]} -gt 0 ]; then
    log_ok "Container '${AXON_CONTAINER_NAME}' started (volumes: ~/CONTEXT → /CONTEXT, ${AXON_WORKSPACE} → /WORKSPACE)."
else
    log_ok "Container '${AXON_CONTAINER_NAME}' started (volume: ~/CONTEXT → /CONTEXT)."
fi

# ==============================================================================
# STEP 3: Wait for the Python backend to be ready
# ==============================================================================
log_info "Waiting for Python backend to be ready on port ${AXON_PORT}..."

elapsed=0
while [ $elapsed -lt $MAX_WAIT_SECONDS ]; do
    if curl -sf "http://localhost:${AXON_PORT}/api/v1/health" >/dev/null 2>&1; then
        log_ok "Python backend is healthy! (${elapsed}s)"
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
    echo -ne "  ⏳ Waiting... (${elapsed}s / ${MAX_WAIT_SECONDS}s)\r"
done

if [ $elapsed -ge $MAX_WAIT_SECONDS ]; then
    log_error "Python backend did not become healthy within ${MAX_WAIT_SECONDS}s."
    log_error "Check container logs: docker logs ${AXON_CONTAINER_NAME}"
    exit 1
fi

# ==============================================================================
# STEP 4: Launch the Go Proxy (foreground — VS Code Copilot connects here)
# ==============================================================================
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  🎯 MCP Axon Environment is READY${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Python Backend : http://localhost:${AXON_PORT}"
echo -e "  Go Proxy       : launching now (stdin/stdout for Copilot SDK)"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

export AXON_BACKEND_URL="http://localhost:${AXON_PORT}/mcp"
exec "${GO_BINARY}"
