#!/usr/bin/env bash
# ==============================================================================
# 🧪 Kubernetes Stress Test — Setup Script
# Clones the Kubernetes source code into ~/CONTEXT for large-scale analysis
# ==============================================================================
set -euo pipefail

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[✓]${NC}     $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[✗]${NC}     $*"; }

CONTEXT_DIR="${HOME}/CONTEXT"
K8S_DIR="${CONTEXT_DIR}/kubernetes"

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  🧪 Kubernetes Stress Test — Preparation${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ── Step 1: Create ~/CONTEXT if needed ────────────────────────────────────────
if [ ! -d "${CONTEXT_DIR}" ]; then
    log_info "Creating directory ${CONTEXT_DIR}..."
    mkdir -p "${CONTEXT_DIR}"
    log_ok "Directory created: ${CONTEXT_DIR}"
else
    log_ok "Directory already exists: ${CONTEXT_DIR}"
fi

# ── Step 2: Clone Kubernetes (shallow clone) ──────────────────────────────────
if [ -d "${K8S_DIR}" ]; then
    log_warn "Kubernetes repository already exists at ${K8S_DIR}."
    log_warn "Skipping clone. Delete it manually if you want a fresh copy."
else
    log_info "Cloning Kubernetes (shallow clone — depth 1)..."
    log_info "This may take a few minutes depending on your connection..."
    git clone --depth 1 https://github.com/kubernetes/kubernetes.git "${K8S_DIR}"
    log_ok "Kubernetes cloned successfully!"
fi

# ── Step 3: Summary ──────────────────────────────────────────────────────────
K8S_FILE_COUNT=$(find "${K8S_DIR}" -type f | wc -l | tr -d ' ')
K8S_SIZE=$(du -sh "${K8S_DIR}" 2>/dev/null | cut -f1)

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅ Kubernetes Stress Test is READY${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  📁 Path          : ${K8S_DIR}"
echo -e "  📊 Total files   : ${K8S_FILE_COUNT}"
echo -e "  💾 Size on disk  : ${K8S_SIZE}"
echo ""
echo -e "  ${CYAN}▶ Next step:${NC} Launch the MCP environment with:"
echo -e "    ${GREEN}./start_mcp_environment.sh${NC}"
echo ""
echo -e "  The volume mount will expose ~/CONTEXT → /CONTEXT inside Docker,"
echo -e "  allowing Tree-sitter to analyze the entire Kubernetes codebase."
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
