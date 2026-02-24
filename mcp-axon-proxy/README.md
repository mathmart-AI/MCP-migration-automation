# `mcp-axon-proxy` — Guide de Production

> **Architecture Zero Egress** : Un proxy Go (Copilot SDK) branché sur un backend FastAPI/Tree-sitter (Axon) en Docker. **Aucune donnée ne quitte votre réseau local.** Le LLM est fourni exclusivement par le SDK GitHub Copilot de votre Enterprise.

---

## ⚡ Quick Start — Commandes Prêtes à l'Emploi

> Tout ce dont vous avez besoin pour démarrer demain matin, dans l'ordre.

### 1. Démarrer l'infrastructure (Docker + Go Proxy)

```bash
cd ~/work/MCP/mcp-axon-proxy
./scripts/start_mcp_environment.sh &
```

### 2. Indexer vos projets dans Axon

```bash
# Remplacez "helm-platform" et "app_a_migrer" par vos vrais dossiers dans ~/CONTEXT
curl -s -X POST "http://localhost:8000/api/v1/repositories" \
  -H "Content-Type: application/json" \
  -d '{"path": "/CONTEXT/helm-platform", "name": "helm-platform"}' | jq .

curl -s -X POST "http://localhost:8000/api/v1/repositories" \
  -H "Content-Type: application/json" \
  -d '{"path": "/CONTEXT/app_a_migrer", "name": "app-migration"}' | jq .
```

### 3. Builder le CLI (une seule fois)

```bash
go build -o axon-cli ./cmd/cli
```

### 4. Lancer une mission

```bash
# Mission Découverte Helm (agent_helm_architect)
AXON_BACKEND_URL="http://localhost:8000/mcp" \
  ./axon-cli --mission missions/MISSION_DISCOVERY.md \
             --role agent_helm_architect \
             --model chatgpt-5mini

# Mission Migration Legacy (agent_migration_specialist)
AXON_BACKEND_URL="http://localhost:8000/mcp" \
  ./axon-cli --mission missions/MISSION_MIGRATE_APP.md \
             --role agent_migration_specialist \
             --model chatgpt-5mini
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│            Architecture "Zero Egress"                           │
│                                                                 │
│  VS Code / axon-cli                                             │
│       │                                                         │
│       ▼  (MCP Protocol — stdio)                                 │
│  ┌────────────────────────────────┐                             │
│  │     mcp-axon-proxy (Go)        │  ← GitHub Copilot SDK       │
│  │  • Authentification Copilot    │    (votre compte Pro/Ent.)  │
│  │  • Personas / Agents           │                             │
│  │  • Relay JSON-RPC → Backend    │                             │
│  └──────────────┬─────────────────┘                             │
│                 │ HTTP localhost:8000/mcp                        │
│                 ▼                                               │
│  ┌────────────────────────────────┐                             │
│  │  axon-mcp-backend (Docker)     │  ← Axon.MCP.Server          │
│  │  • FastAPI + Tree-sitter       │    (Python FastAPI)         │
│  │  • Analyse statique locale     │                             │
│  │  • Volume: ~/CONTEXT → /CONTEXT│                             │
│  └────────────────────────────────┘                             │
│                                                                 │
│  🔒 Aucun appel sortant vers OpenAI / Anthropic / OpenRouter    │
└─────────────────────────────────────────────────────────────────┘
```

**Agents disponibles** (`--role`) :

| Nom du rôle | Description |
|---|---|
| `agent_helm_architect` | Analyse de charts Helm complexes (library, Vault, Tekton) |
| `agent_migration_specialist` | Migration legacy Java/XML/Properties → Helm/Go-CLI |
| `persona_k8s_expert` | DevOps / Kubernetes / Prometheus expert |
| `persona_golang_expert` | Architecture Go, call graph, concurrence |
| `persona_webapp_expert` | React/Vite, migration, architecture frontend |
| `agent_kubernetes_platform` | Exécution de scripts Kubernetes (K3D, Helm) |

---

## Prérequis

1. **Docker Desktop** — [téléchargement](https://www.docker.com/products/docker-desktop/) — doit être en cours d'exécution
2. **Go ≥ 1.21** — [téléchargement](https://go.dev/dl/)
3. **Authentification GitHub Copilot** :
   ```bash
   gh auth login
   # OU
   gh copilot auth
   ```
   Vous devez avoir un compte **Copilot Pro** ou **Copilot Enterprise** actif.

4. **Dossier de contexte** : Créez `~/CONTEXT/` et placez-y vos projets à analyser :
   ```bash
   mkdir -p ~/CONTEXT
   ```

---

## Démarrage de l'Infrastructure

Lance le backend Python (Docker) + compile et démarre le proxy Go en une seule commande :

```bash
cd ~/work/MCP/mcp-axon-proxy
./scripts/start_mcp_environment.sh
```

Ce script :
1. Compile le binaire Go (`mcp-axon-proxy`)
2. Construit l'image Docker du backend Axon
3. Lance le container Docker avec `~/CONTEXT` monté en `/CONTEXT`
4. Attend que le backend soit healthy
5. Lance le proxy Go (point d'entrée MCP pour VS Code/Copilot)

> **En tâche de fond** (pour utiliser `axon-cli` en parallèle) :
> ```bash
> ./scripts/start_mcp_environment.sh &
> ```

---

## Indexation Locale (forcer l'analyse par Axon)

Pour que l'agent puisse analyser vos projets dans `~/CONTEXT`, forcez l'indexation via Axon :

```bash
# Indexer le dossier ~/CONTEXT/helm-platform (exemple)
curl -s -X POST "http://localhost:8000/api/v1/repositories" \
  -H "Content-Type: application/json" \
  -d '{"path": "/CONTEXT/helm-platform", "name": "helm-platform"}' | jq .

# Indexer un dossier application (example)
curl -s -X POST "http://localhost:8000/api/v1/repositories" \
  -H "Content-Type: application/json" \
  -d '{"path": "/CONTEXT/app_a_migrer", "name": "app-migration"}' | jq .
```

> **Astuce** : Le chemin doit être `/CONTEXT/...` (chemin dans le container), pas `~/CONTEXT/...`.
> Axon analyse le code localement avec Tree-sitter — **aucune donnée ne sort du container**.

---

## Exécution des Missions (axon-cli)

### Build du CLI (une seule fois)

```bash
cd ~/work/MCP/mcp-axon-proxy
go build -o axon-cli ./cmd/cli
```

### Mission 1 — Audit de la Helm Platform

**Agent** : `agent_helm_architect`  
**Fichier mission** : `missions/MISSION_DISCOVERY.md`

```bash
AXON_BACKEND_URL="http://localhost:8000/mcp" \
  ./axon-cli \
  --mission missions/MISSION_DISCOVERY.md \
  --role agent_helm_architect \
  --model chatgpt-5mini
```

### Mission 2 — Migration d'Application Legacy

**Agent** : `agent_migration_specialist`  
**Fichier mission** : `missions/MISSION_MIGRATE_APP.md`

```bash
AXON_BACKEND_URL="http://localhost:8000/mcp" \
  ./axon-cli \
  --mission missions/MISSION_MIGRATE_APP.md \
  --role agent_migration_specialist \
  --model chatgpt-5mini
```

> **Changer de modèle** : Utilisez `--model gpt-4o` ou `--model chatgpt-5` selon votre licence Copilot.

---

## Structure du Repository

```
mcp-axon-proxy/
├── cmd/
│   ├── server/       # Serveur MCP (proxy Go — point d'entrée VS Code)
│   ├── cli/          # CLI headless (axon-cli)
│   └── test/         # Tests d'intégration
├── internal/
│   ├── prompts/      # Définition des agents/personas (prompts.go)
│   └── tools/        # Dynamic tool registration depuis Axon backend
├── missions/         # Fichiers de mission (.md)
│   ├── MISSION_DISCOVERY.md
│   ├── MISSION_MIGRATE_APP.md
│   └── MISSION_K3D.md
├── scripts/          # Scripts utilitaires
│   └── start_mcp_environment.sh  ← POINT D'ENTRÉE PRINCIPAL
├── go.mod
└── README.md         ← CE FICHIER
```

---

## Dépannage

| Problème | Solution |
|---|---|
| `docker: command not found` | Démarrer Docker Desktop |
| Backend ne démarre pas | `docker logs axon-mcp-backend` |
| `gh auth: not logged in` | `gh auth login --scopes copilot` |
| CLI retourne 0 caractères | Vérifier que le container est healthy : `curl http://localhost:8000/api/v1/health` |
| Axon ne voit pas les fichiers | Vérifier que `~/CONTEXT/` existe et que l'indexation a bien été lancée via `curl` |
