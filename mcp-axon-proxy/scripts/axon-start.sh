#!/usr/bin/env bash
# ==============================================================================
# 🚀 axon-start.sh — Script tout-en-un pour démarrer Axon depuis n'importe quel dossier
#
# Usage:
#   cd ~/works/mon-projet && axon-start.sh        # Monte le dossier courant en /WORKSPACE
#   AXON_WORKSPACE=~/works/kong axon-start.sh     # Monte un dossier spécifique
#
# Note: si le script n'est pas exécutable, lancez d'abord :
#   chmod +x ~/MCP-migration-automation/mcp-axon-proxy/scripts/axon-start.sh
#
# Ce script :
#   1. Démarre le backend Docker avec ~/CONTEXT ET le dossier courant monté en /WORKSPACE
#   2. Attend que le backend soit healthy (http://localhost:8000/api/v1/health)
#   3. Indexe automatiquement le dossier courant dans Axon via l'API REST
#   4. Affiche les instructions pour connecter gh copilot / VS Code
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
AXON_PORT="${AXON_PORT:-8000}"
AXON_CONTAINER_NAME="axon-mcp-backend"
AXON_IMAGE_NAME="axon-mcp-backend"
AXON_BACKEND_DIR="${PROJECT_ROOT}/../Axon.MCP.Server"
MAX_WAIT_SECONDS=60

# Le workspace à monter et indexer = dossier courant (ou $AXON_WORKSPACE si défini)
AXON_WORKSPACE="${AXON_WORKSPACE:-$(pwd)}"
WORKSPACE_NAME="${WORKSPACE_NAME:-$(basename "${AXON_WORKSPACE}")}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[✓]${NC}     $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[✗]${NC}     $*"; }

# ==============================================================================
# STEP 0: Vérifications préalables
# ==============================================================================
log_info "Vérification des prérequis..."

if ! command -v docker &>/dev/null; then
    log_error "Docker n'est pas installé. Installez Docker Desktop depuis https://www.docker.com/products/docker-desktop/"
    exit 1
fi

if ! docker info &>/dev/null; then
    log_error "Le daemon Docker n'est pas démarré. Démarrez Docker Desktop d'abord."
    exit 1
fi
log_ok "Docker est disponible."

if ! [ -d "${AXON_WORKSPACE}" ]; then
    log_error "Le dossier workspace n'existe pas : ${AXON_WORKSPACE}"
    exit 1
fi
log_ok "Workspace : ${AXON_WORKSPACE}"

# ==============================================================================
# STEP 1: Démarrer (ou réutiliser) le container Docker
# ==============================================================================
if docker ps -q --filter "name=${AXON_CONTAINER_NAME}" 2>/dev/null | grep -q .; then
    log_warn "Le container '${AXON_CONTAINER_NAME}' tourne déjà — vérification de la santé..."
else
    # Supprimer un container arrêté s'il existe
    if docker ps -aq --filter "name=${AXON_CONTAINER_NAME}" 2>/dev/null | grep -q .; then
        log_warn "Suppression du container arrêté '${AXON_CONTAINER_NAME}'..."
        docker rm "${AXON_CONTAINER_NAME}" >/dev/null 2>&1 || true
    fi

    # Construire l'image si nécessaire
    if ! docker image inspect "${AXON_IMAGE_NAME}" &>/dev/null; then
        log_info "Construction de l'image Docker '${AXON_IMAGE_NAME}'..."
        if [ ! -d "${AXON_BACKEND_DIR}" ]; then
            log_error "Dossier backend introuvable : ${AXON_BACKEND_DIR}"
            exit 1
        fi
        docker build -t "${AXON_IMAGE_NAME}" "${AXON_BACKEND_DIR}"
        log_ok "Image Docker construite."
    else
        log_ok "Image Docker '${AXON_IMAGE_NAME}' déjà présente."
    fi

    log_info "Démarrage du backend sur le port ${AXON_PORT}..."
    log_info "  ~/CONTEXT   → /CONTEXT   (projets copiés manuellement)"
    log_info "  ${AXON_WORKSPACE} → /WORKSPACE (dossier courant)"

    docker run -d \
        --name "${AXON_CONTAINER_NAME}" \
        -p "${AXON_PORT}:${AXON_PORT}" \
        -v "${HOME}/CONTEXT:/CONTEXT" \
        -v "${AXON_WORKSPACE}:/WORKSPACE" \
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
    log_ok "Container '${AXON_CONTAINER_NAME}' démarré."
fi

# ==============================================================================
# STEP 2: Attendre que le backend soit healthy
# ==============================================================================
log_info "En attente du backend Axon (max ${MAX_WAIT_SECONDS}s)..."

elapsed=0
while [ $elapsed -lt $MAX_WAIT_SECONDS ]; do
    if curl -sf "http://localhost:${AXON_PORT}/api/v1/health" >/dev/null 2>&1; then
        log_ok "Backend Axon opérationnel ! (${elapsed}s)"
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
    echo -ne "  ⏳ En attente... (${elapsed}s / ${MAX_WAIT_SECONDS}s)\r"
done

if [ $elapsed -ge $MAX_WAIT_SECONDS ]; then
    log_error "Le backend n'a pas démarré dans les ${MAX_WAIT_SECONDS}s impartis."
    log_error "Vérifiez les logs : docker logs ${AXON_CONTAINER_NAME}"
    exit 1
fi

# ==============================================================================
# STEP 3: Indexer automatiquement le dossier courant dans Axon
# ==============================================================================
log_info "Indexation du workspace '${WORKSPACE_NAME}' dans Axon (/WORKSPACE)..."

INDEX_RESPONSE=$(curl -sf -X POST "http://localhost:${AXON_PORT}/api/v1/repositories" \
    -H "Content-Type: application/json" \
    -d "{\"path\": \"/WORKSPACE\", \"name\": \"${WORKSPACE_NAME}\"}" 2>&1 || true)

if echo "${INDEX_RESPONSE}" | grep -qE '"id"|"name"'; then
    log_ok "Workspace '${WORKSPACE_NAME}' indexé avec succès."
else
    log_warn "Indexation retournée : ${INDEX_RESPONSE:-<réponse vide>}"
    log_warn "Le workspace sera accessible via /WORKSPACE dans le container."
    log_warn "Relancez manuellement si besoin :"
    log_warn "  curl -X POST http://localhost:${AXON_PORT}/api/v1/repositories \\"
    log_warn "    -H 'Content-Type: application/json' \\"
    log_warn "    -d '{\"path\": \"/WORKSPACE\", \"name\": \"${WORKSPACE_NAME}\"}'"
fi

# ==============================================================================
# STEP 4: Afficher les instructions de connexion
# ==============================================================================
echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  🎯 Axon MCP est PRÊT${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Backend MCP   : ${CYAN}http://localhost:${AXON_PORT}/mcp${NC}"
echo -e "  Health check  : ${CYAN}http://localhost:${AXON_PORT}/api/v1/health${NC}"
echo -e "  Workspace     : ${CYAN}${AXON_WORKSPACE}${NC} → /WORKSPACE"
echo ""
echo -e "${BOLD}Pour connecter VS Code Copilot Chat :${NC}"
echo -e "  Copiez ${CYAN}.vscode/mcp.json${NC} dans votre projet :"
echo -e '  { "mcpServers": { "axon": { "url": "http://localhost:'"${AXON_PORT}"'/mcp" } } }'
echo ""
echo -e "${BOLD}Pour utiliser axon-server (chat interactif) :${NC}"
echo -e "  ${CYAN}AXON_BACKEND_URL=http://localhost:${AXON_PORT}/mcp axon-server${NC}"
echo ""
echo -e "${BOLD}Pour utiliser axon-cli (mission automatisée) :${NC}"
echo -e "  ${CYAN}AXON_BACKEND_URL=http://localhost:${AXON_PORT}/mcp axon-cli --mission <fichier.md> --role <agent>${NC}"
echo ""
echo -e "${BOLD}Pour arrêter le backend :${NC}"
echo -e "  ${CYAN}docker stop ${AXON_CONTAINER_NAME}${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  💡 Pour rendre AXON_BACKEND_URL disponible dans votre shell courant :"
echo -e "     ${CYAN}export AXON_BACKEND_URL=http://localhost:${AXON_PORT}/mcp${NC}"
echo ""
