#!/usr/bin/env bash
# ==============================================================================
# 🚀 K3d Dev Cluster — Setup Script
# Cluster : dev-cluster | Ports: 80 (HTTP) / 443 (HTTPS)
# Stack   : Traefik (ingress) + kube-prometheus-stack (monitoring)
# ==============================================================================
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[✓]${NC}     $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[✗]${NC}     $*"; }
log_section() { echo -e "\n${BOLD}${CYAN}━━━  $*  ━━━${NC}"; }

CLUSTER_NAME="dev-cluster"
MONITORING_NS="monitoring"
HELM_RELEASE="prom-stack"
VALUES_FILE="$(dirname "$0")/values-prometheus.yaml"

# ==============================================================================
# STEP 0 — Prerequisites
# ==============================================================================
log_section "Checking prerequisites"

for tool in docker k3d kubectl helm; do
    if ! command -v "$tool" &>/dev/null; then
        log_error "'$tool' is not installed or not in PATH."
        case "$tool" in
            docker) echo "  → https://www.docker.com/products/docker-desktop/" ;;
            k3d)    echo "  → brew install k3d  OR  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash" ;;
            kubectl)echo "  → brew install kubectl" ;;
            helm)   echo "  → brew install helm" ;;
        esac
        exit 1
    fi
    log_ok "$tool: $(command $tool version --short 2>/dev/null | head -1 || $tool version 2>/dev/null | head -1 || echo 'found')"
done

if ! docker info &>/dev/null; then
    log_error "Docker daemon is not running. Start Docker Desktop first."
    exit 1
fi
log_ok "Docker daemon is running."

# ==============================================================================
# STEP 1 — Create k3d cluster
# ==============================================================================
log_section "K3d cluster: $CLUSTER_NAME"

if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
    log_warn "Cluster '${CLUSTER_NAME}' already exists — skipping creation."
else
    log_info "Creating cluster '${CLUSTER_NAME}' (1 server + 1 agent, ports 80/443)..."
    k3d cluster create "${CLUSTER_NAME}" \
        --servers 1 \
        --agents 1 \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer" \
        --k3s-arg "--disable=traefik@server:0" \
        --wait
    log_ok "Cluster '${CLUSTER_NAME}' created."
fi

# Set current context
kubectl config use-context "k3d-${CLUSTER_NAME}" &>/dev/null
log_ok "kubectl context set to 'k3d-${CLUSTER_NAME}'."

# ==============================================================================
# STEP 2 — Verify API server
# ==============================================================================
log_section "Kubernetes API health check"

API_URL=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)
log_info "API server: ${API_URL}"

if kubectl cluster-info &>/dev/null; then
    log_ok "API server is reachable."
else
    log_error "Cannot reach Kubernetes API. Check cluster status."
    exit 1
fi

kubectl get nodes -o wide
echo ""

# ==============================================================================
# STEP 3 — Install Traefik v2 via Helm (ingress controller)
# ==============================================================================
log_section "Traefik Ingress Controller"

helm repo add traefik https://traefik.github.io/charts --force-update &>/dev/null
helm repo update &>/dev/null

if helm status traefik -n kube-system &>/dev/null 2>&1; then
    log_warn "Traefik already installed — skipping."
else
    log_info "Installing Traefik..."
    helm upgrade --install traefik traefik/traefik \
        --namespace kube-system \
        --set ingressClass.enabled=true \
        --set ingressClass.isDefaultClass=true \
        --set service.type=LoadBalancer \
        --wait --timeout 3m
    log_ok "Traefik installed."
fi

# ==============================================================================
# STEP 4 — Install kube-prometheus-stack (lightweight)
# ==============================================================================
log_section "kube-prometheus-stack (monitoring)"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update &>/dev/null
helm repo update &>/dev/null

kubectl get namespace "${MONITORING_NS}" &>/dev/null || \
    kubectl create namespace "${MONITORING_NS}"

if [ ! -f "${VALUES_FILE}" ]; then
    log_error "Values file not found: ${VALUES_FILE}"
    exit 1
fi

log_info "Installing/upgrading ${HELM_RELEASE} in namespace ${MONITORING_NS}..."
helm upgrade --install "${HELM_RELEASE}" prometheus-community/kube-prometheus-stack \
    --namespace "${MONITORING_NS}" \
    --values "${VALUES_FILE}" \
    --wait --timeout 10m

log_ok "kube-prometheus-stack deployed."

# ==============================================================================
# STEP 5 — Validation
# ==============================================================================
log_section "Validation"

echo ""
log_info "Waiting for monitoring pods to be ready (up to 5 min)..."
kubectl wait --for=condition=Ready pods --all \
    -n "${MONITORING_NS}" --timeout=300s 2>/dev/null || true

echo ""
echo -e "${BOLD}Pod status in namespace '${MONITORING_NS}':${NC}"
kubectl get pods -n "${MONITORING_NS}" -o wide

echo ""
echo -e "${BOLD}Services:${NC}"
kubectl get svc -n "${MONITORING_NS}"

echo ""
# Check Grafana
GRAFANA_POD=$(kubectl get pod -n "${MONITORING_NS}" -l "app.kubernetes.io/name=grafana" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "${GRAFANA_POD}" ]; then
    GRAFANA_READY=$(kubectl get pod "${GRAFANA_POD}" -n "${MONITORING_NS}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "${GRAFANA_READY}" = "True" ]; then
        log_ok "Grafana pod is Ready: ${GRAFANA_POD}"
    else
        log_warn "Grafana pod not yet Ready: ${GRAFANA_POD}"
    fi
fi

# Check Prometheus
PROM_POD=$(kubectl get pod -n "${MONITORING_NS}" -l "app.kubernetes.io/name=prometheus" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "${PROM_POD}" ]; then
    PROM_READY=$(kubectl get pod "${PROM_POD}" -n "${MONITORING_NS}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "${PROM_READY}" = "True" ]; then
        log_ok "Prometheus pod is Ready: ${PROM_POD}"
    else
        log_warn "Prometheus pod not yet Ready: ${PROM_POD}"
    fi
fi

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅  dev-cluster is UP and monitoring is deployed${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Cluster context  : k3d-${CLUSTER_NAME}"
echo -e "  API server       : ${API_URL}"
echo -e "  Ingress HTTP     : http://localhost:80"
echo -e "  Ingress HTTPS    : https://localhost:443"
echo ""
echo -e "  ${CYAN}Port-forwards (manual):${NC}"
echo -e "    Grafana    →  kubectl port-forward svc/${HELM_RELEASE}-grafana 3000:80 -n ${MONITORING_NS}"
echo -e "    Prometheus →  kubectl port-forward svc/${HELM_RELEASE}-kube-prom-prometheus 9090 -n ${MONITORING_NS}"
echo -e "    Alertmanager → kubectl port-forward svc/${HELM_RELEASE}-kube-prom-alertmanager 9093 -n ${MONITORING_NS}"
echo ""
echo -e "  ${CYAN}Grafana credentials:${NC}  admin / dev-admin"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
