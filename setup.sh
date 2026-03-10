#!/usr/bin/env bash
# ==============================================================================
# 🚀 Axon Copilot — Setup & Installation Script
# This script sets up the local environment and global CLI plugin
# Run from repository root.
# ==============================================================================
set -euo pipefail

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AXON_PROXY_DIR="${SCRIPT_DIR}/mcp-axon-proxy"

echo -e "${CYAN}"
echo "    ___                     ______            _ __      __   "
echo "   /   | _  ______  ____   / ____/___  ____  (_) /___  / /_  "
echo "  / /| | | |/_/ _ \/ __ \ / /   / __ \/ __ \/ / / __ \/ __/  "
echo " / ___ |_>  </  __/ / / // /___/ /_/ / /_/ / / / /_/ / /_    "
echo "/_/  |_/_/|_|\___/_/ /_/ \____/\____/ .___/_/_/\____/\__/    "
echo "                                   /_/                       "
echo -e "${NC}"
echo "Installer started..."
echo "=============================================================================="

# ── 1. OS Detection ──────────────────────────────────────────────────────────
log_info "Detecting Operating System..."
OS_TYPE=$(uname -s)
IS_WSL=false

if [[ "${OS_TYPE}" == "Linux" ]]; then
    if grep -q microsoft /proc/version 2>/dev/null; then
        IS_WSL=true
        log_ok "OS: Windows Subsystem for Linux (WSL 2)"
    else
        log_ok "OS: Linux"
    fi
elif [[ "${OS_TYPE}" == "Darwin" ]]; then
    log_ok "OS: MacOS"
else
    log_warn "Unknown OS: ${OS_TYPE}. Proceeding with caution..."
fi

# ── 2. Dependency Checks ─────────────────────────────────────────────────────
log_info "Verifying dependencies..."

# Go
if ! command -v go &>/dev/null; then
    log_error "Go is not installed. Please install Go >= 1.21."
    exit 1
fi
log_ok "Go found: $(go version)"

# Docker
if ! command -v docker &>/dev/null; then
    log_error "Docker is not installed."
    echo "  → MacOS/Windows: Install Docker Desktop"
    echo "  → Linux: Install Docker Engine"
    exit 1
fi

if ! docker info &>/dev/null; then
    if [ "$IS_WSL" = true ]; then
        log_error "Docker daemon is not running. Start Docker Desktop and ensure WSL integration is enabled."
    else
        log_error "Docker daemon is not running. Please start it."
    fi
    exit 1
fi
log_ok "Docker is running."

# GitHub CLI & Copilot
if ! command -v gh &>/dev/null; then
    log_warn "GitHub CLI (gh) not found. You will need it to authenticate Copilot."
else
    log_ok "GitHub CLI found."
fi

if ! command -v copilot &>/dev/null && ! gh extension list | grep -q copilot; then
    log_warn "GitHub Copilot CLI not detected. You will need to install it: gh extension install github/gh-copilot"
else
    log_ok "Copilot CLI available."
fi

# ── 3. Build Go Proxy ────────────────────────────────────────────────────────
log_info "Building Axon MCP Proxy..."
if [ ! -d "${AXON_PROXY_DIR}" ]; then
    log_error "Proxy directory not found at ${AXON_PROXY_DIR}."
    exit 1
fi

(cd "${AXON_PROXY_DIR}" && go build -o "mcp-axon-proxy" ./cmd/server)
if [ -f "${AXON_PROXY_DIR}/mcp-axon-proxy" ]; then
    log_ok "Axon Go Proxy compiled successfully."
else
    log_error "Compilation failed."
    exit 1
fi

# ── 4. Generate Native Plugin Config ─────────────────────────────────────────
log_info "Configuring Axon as a native Copilot Plugin..."

PLUGIN_FILE="${AXON_PROXY_DIR}/plugin.json"
cat << EOF > "${PLUGIN_FILE}"
{
  "name": "axon",
  "version": "1.0.0",
  "description": "Axon Zero-Egress Code Intelligence Plugin",
  "type": "mcp",
  "mcpServers": {
    "axon": {
      "command": "${AXON_PROXY_DIR}/mcp-axon-proxy"
    }
  }
}
EOF
log_ok "Generated plugin.json at ${PLUGIN_FILE}"

# ── 5. Install Plugin ────────────────────────────────────────────────────────
log_info "Installing plugin into Copilot CLI..."
if command -v copilot &>/dev/null || gh extension list | grep -q copilot; then
    copilot plugin install "${AXON_PROXY_DIR}"
    log_ok "Plugin globally installed!"
else
    log_error "Could not install plugin automatically (Copilot CLI not found or authenticated)."
    echo "You can manually install it later by running: copilot plugin install ${AXON_PROXY_DIR}"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  🎉 Installation complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Next steps:"
echo -e "1. Run the backend environment:    cd mcp-axon-proxy && ./scripts/start_mcp_environment.sh &"
echo -e "2. In any directory, just type:    copilot\n"
