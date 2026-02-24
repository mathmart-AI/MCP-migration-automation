# MCP Migration Automation

> **Architecture Zero Egress** — Un système d'agents IA pour l'analyse et la migration de code legacy, fonctionnant entièrement en local via le SDK GitHub Copilot. Aucune donnée n'est envoyée à OpenAI, Anthropic ou tout autre LLM externe.

---

## Composants

```
MCP/
├── Axon.MCP.Server/      # Backend Python — Analyse statique Tree-sitter (Docker)
├── mcp-axon-proxy/       # Proxy Go — SDK Copilot + Agents/Personas CLI
└── mcp-migration-server/ # Serveur MCP dédié migration (go-platform CLI)
```

| Composant | Rôle | Tech |
|---|---|---|
| `Axon.MCP.Server` | Analyse statique locale (symboles, call graph, search) | Python, FastAPI, Tree-sitter |
| `mcp-axon-proxy` | Proxy MCP + Agents IA headless (`axon-cli`) | Go, GitHub Copilot SDK |
| `mcp-migration-server` | Outils MCP dédiés (go-platform, resources migration) | Go |

---

## ⚡ Quick Start

> **Prérequis** : Docker Desktop + Go ≥ 1.21 + `gh auth login` (compte Copilot Pro/Enterprise)

### 1. Cloner & se positionner

```bash
git clone git@github.com:mathmart-AI/MCP-migration-automation.git
cd MCP-migration-automation
```

### 2. Démarrer l'infrastructure (Docker backend + Go proxy)

```bash
cd mcp-axon-proxy
./scripts/start_mcp_environment.sh &
```

Ce script compile le binaire Go, build l'image Docker Axon, monte `~/CONTEXT` et attend que le backend soit healthy.

### 3. Indexer vos projets dans Axon

```bash
# Adapter les chemins à vos dossiers dans ~/CONTEXT
curl -s -X POST "http://localhost:8000/api/v1/repositories" \
  -H "Content-Type: application/json" \
  -d '{"path": "/CONTEXT/helm-platform", "name": "helm-platform"}' | jq .

curl -s -X POST "http://localhost:8000/api/v1/repositories" \
  -H "Content-Type: application/json" \
  -d '{"path": "/CONTEXT/app_a_migrer", "name": "app-migration"}' | jq .
```

### 4. Builder le CLI (une seule fois)

```bash
cd mcp-axon-proxy
go build -o axon-cli ./cmd/cli
```

### 5. Lancer une mission agent

```bash
# Audit de la Helm Platform
AXON_BACKEND_URL="http://localhost:8000/mcp" \
  ./axon-cli --mission missions/MISSION_DISCOVERY.md \
             --role agent_helm_architect \
             --model chatgpt-5mini

# Migration d'une application legacy Java → Helm
AXON_BACKEND_URL="http://localhost:8000/mcp" \
  ./axon-cli --mission missions/MISSION_MIGRATE_APP.md \
             --role agent_migration_specialist \
             --model chatgpt-5mini
```

---

## Agents disponibles

| `--role` | Description |
|---|---|
| `agent_helm_architect` | Analyse Helm charts complexes (library, Vault, Tekton) |
| `agent_migration_specialist` | Rétro-ingénierie Java/XML/Properties → Helm/Go-CLI |
| `persona_k8s_expert` | DevOps / Kubernetes / Prometheus |
| `persona_golang_expert` | Architecture Go, call graph, concurrence |
| `persona_webapp_expert` | React/Vite, migrations frontend |
| `agent_kubernetes_platform` | Exécution de scripts Kubernetes (K3D, Helm) |

---

## Architecture Zero Egress

```
  VS Code / axon-cli
       │
       ▼ (MCP — stdio)
  ┌─────────────────────────┐
  │   mcp-axon-proxy (Go)   │ ← GitHub Copilot SDK (Pro/Enterprise)
  │   Personas / Agents      │   Aucune clé LLM externe requise
  └──────────┬──────────────┘
             │ HTTP :8000/mcp
             ▼
  ┌─────────────────────────┐
  │  Axon.MCP.Server        │ ← Docker
  │  FastAPI + Tree-sitter   │   ~/CONTEXT monté en /CONTEXT
  │  Analyse 100% locale     │   Zéro appel réseau sortant
  └─────────────────────────┘
```

🔒 `openai`, `anthropic`, `openrouter` — **imports supprimés** du backend Python.

---

## Missions

| Fichier | Agent | Description |
|---|---|---|
| `missions/MISSION_DISCOVERY.md` | `agent_helm_architect` | Audit complet d'une Helm Platform |
| `missions/MISSION_MIGRATE_APP.md` | `agent_migration_specialist` | Migration app legacy vers Helm |
| `missions/MISSION_K3D.md` | `persona_k8s_expert` | Déploiement K3D + Prometheus |

---

## Dépannage rapide

| Problème | Commande |
|---|---|
| Backend pas healthy | `docker logs axon-mcp-backend` |
| Vérifier santé backend | `curl http://localhost:8000/api/v1/health` |
| Voir les binaires compilés | `ls -la mcp-axon-proxy/axon-cli` |
| Re-auth Copilot | `gh auth login --scopes copilot` |
