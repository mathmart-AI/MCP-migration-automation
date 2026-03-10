# Intégration Copilot & VS Code avec Axon MCP

> Ce document explique comment utiliser Axon MCP depuis **n'importe quel dossier** et comment le connecter à **VS Code Copilot Chat** ou à **`gh copilot`**.

---

## 1. Le problème : 3 limitations de l'architecture initiale

### Limitation 1 — Contrainte `~/CONTEXT`

Le script `scripts/start_mcp_environment.sh` ne montait que `~/CONTEXT` → `/CONTEXT` dans le container Docker. Pour analyser un projet dans `~/works/kong/`, l'utilisateur devait d'abord copier ou créer un symlink dans `~/CONTEXT`. Ce n'est pas ergonomique.

### Limitation 2 — Pas d'intégration avec `gh copilot` / VS Code Copilot Chat

Seuls `axon-cli` (mode mission automatisée) et `axon-server` (mode chat interactif) pouvaient utiliser les tools Axon, car ils embarquent le proxy Go + le SDK Copilot. La CLI officielle `gh copilot` et VS Code Copilot Chat ne savaient pas qu'Axon existait.

Pourtant, `gh copilot` et VS Code Copilot Chat offrent des avantages importants :
- Changement de modèle à la volée
- Intégration native avec l'IDE VS Code
- Écosystème d'extensions GitHub

Le backend Axon supporte **déjà** le transport MCP HTTP (endpoint `/mcp`), mais il manquait la documentation et les fichiers de configuration pour connecter ces clients.

### Limitation 3 — Pas de script simplifié pour démarrer et indexer le dossier courant

L'utilisateur devait exécuter manuellement plusieurs commandes : démarrer Docker, attendre le health check, puis indexer via `curl`. Il manquait un script « one-liner » qui fait tout.

---

## 2. Les solutions apportées

### A. Volume `$AXON_WORKSPACE` dans `start_mcp_environment.sh`

Le script `mcp-axon-proxy/scripts/start_mcp_environment.sh` monte maintenant **deux volumes** :
- `~/CONTEXT` → `/CONTEXT` (comportement existant, rétrocompatible)
- `$AXON_WORKSPACE` → `/WORKSPACE` (nouveau — dossier courant par défaut)

```bash
# Utilisation standard (monte le dossier courant)
cd ~/works/kong
./scripts/start_mcp_environment.sh

# Ou en spécifiant un dossier explicitement
AXON_WORKSPACE=~/works/kong ./scripts/start_mcp_environment.sh
```

Si `AXON_WORKSPACE` n'est pas défini, le dossier courant (`$(pwd)`) est utilisé.

### B. Script tout-en-un `axon-start.sh`

Le script `mcp-axon-proxy/scripts/axon-start.sh` remplace le workflow manuel en trois étapes :

1. Démarre le container Docker avec `~/CONTEXT` ET le dossier courant monté en `/WORKSPACE`
2. Attend que le backend soit healthy (`curl http://localhost:8000/api/v1/health`)
3. Indexe automatiquement le dossier courant dans Axon via l'API REST
4. Affiche les instructions pour connecter `gh copilot` / VS Code

### C. Template `.vscode/mcp.json`

Le fichier `.vscode/mcp.json` à la racine du repo permet à VS Code Copilot Chat de se connecter automatiquement au serveur MCP Axon. Ce fichier peut être copié dans n'importe quel projet.

---

## 3. Guide d'utilisation

### 3.1. Démarrer Axon depuis n'importe quel dossier

```bash
# 1. Rendre le script exécutable (une seule fois)
chmod +x ~/MCP-migration-automation/mcp-axon-proxy/scripts/axon-start.sh

# 2. Créer un alias global (dans ~/.bashrc ou ~/.zshrc)
alias axon-start='~/MCP-migration-automation/mcp-axon-proxy/scripts/axon-start.sh'

# 3. Utiliser depuis n'importe où
cd ~/works/kong
axon-start
# → Démarre Docker, indexe ~/works/kong dans Axon, affiche les instructions
```

Le script affiche un résumé à la fin :

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🎯 Axon MCP est PRÊT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Backend MCP   : http://localhost:8000/mcp
  Health check  : http://localhost:8000/api/v1/health
  Workspace     : /home/user/works/kong → /WORKSPACE
```

### 3.2. Connecter VS Code Copilot Chat à Axon

#### Étape 1 — Démarrer Axon

```bash
cd ~/works/mon-projet
axon-start
```

#### Étape 2 — Ajouter `.vscode/mcp.json` dans votre projet

Copiez le fichier template depuis le repo Axon :

```bash
cp ~/MCP-migration-automation/.vscode/mcp.json ~/works/mon-projet/.vscode/mcp.json
```

Ou créez-le manuellement avec ce contenu :

```json
{
  "mcpServers": {
    "axon": {
      "url": "http://localhost:8000/mcp"
    }
  }
}
```

#### Étape 3 — Ouvrir le projet dans VS Code

```bash
code ~/works/mon-projet
```

VS Code Copilot Chat détectera automatiquement le fichier `.vscode/mcp.json` et proposera de se connecter au serveur MCP Axon. Les tools Axon (`search`, `get_call_graph`, `get_repository_structure`, etc.) seront disponibles dans Copilot Chat.

#### Étape 4 — Utiliser les tools Axon dans Copilot Chat

Dans VS Code, ouvrez Copilot Chat et posez vos questions directement :

```
@copilot Montre-moi l'architecture de ce projet
@copilot Qui appelle la fonction handleAuth ?
@copilot Quels fichiers seraient impactés si je refactore le service d'authentification ?
```

Copilot appellera automatiquement les tools MCP Axon pour analyser votre code.

### 3.3. Utiliser `axon-server` (chat interactif en terminal)

Si vous préférez une interface en terminal sans VS Code :

```bash
# Builder une seule fois
cd ~/MCP-migration-automation/mcp-axon-proxy
go build -o axon-server ./cmd/server
sudo ln -sf $(pwd)/axon-server /usr/local/bin/axon-server

# Démarrer Axon puis lancer le chat
cd ~/works/kong
axon-start
AXON_BACKEND_URL=http://localhost:8000/mcp axon-server
```

```
Axon Proxy Agent ready. Type your prompt (or 'exit' to quit):
> Montre-moi l'architecture de ce projet
> Qui appelle la fonction handleAuth ?
> Quels fichiers seraient impactés si je refactore le middleware ?
> exit
```

### 3.4. Utiliser `axon-cli` et `axon-server` en parallèle

Les deux modes peuvent fonctionner simultanément tant qu'Axon Docker tourne :

```bash
# Terminal 1 — Chat interactif
AXON_BACKEND_URL=http://localhost:8000/mcp axon-server

# Terminal 2 — Mission automatisée en parallèle
AXON_BACKEND_URL=http://localhost:8000/mcp axon-cli \
  --mission ~/MCP-migration-automation/mcp-axon-proxy/missions/MISSION_DISCOVERY.md \
  --role agent_helm_architect \
  --model chatgpt-5mini
```

### 3.5. À propos de `gh copilot` (CLI officielle GitHub)

> ℹ️ La CLI officielle `gh copilot` ne supporte pas encore nativement la connexion à un serveur MCP local. C'est précisément pourquoi le repo Axon fournit ses propres CLI (`axon-cli` et `axon-server`) qui embarquent le SDK Copilot et se connectent directement au backend.

Pour bénéficier des avantages de l'écosystème Copilot (changement de modèle, intégration IDE) tout en utilisant les tools Axon :

- **Dans VS Code** : utilisez **VS Code Copilot Chat** avec le fichier `.vscode/mcp.json` (voir section 3.2). C'est le moyen recommandé pour combiner Copilot et Axon.
- **En terminal** : utilisez **`axon-server`** pour un chat interactif avec les tools Axon (section 3.3).

Consultez la [documentation officielle GitHub Copilot](https://docs.github.com/copilot) pour suivre les évolutions du support MCP dans `gh copilot`.

---

## 4. Architecture avant / après

### AVANT

```
  axon-cli / axon-server
        │
        ▼ (MCP — stdio)
  ┌─────────────────────────┐
  │   mcp-axon-proxy (Go)   │  ← GitHub Copilot SDK
  └──────────┬──────────────┘
             │ HTTP :8000/mcp
             ▼
  ┌─────────────────────────┐
  │  Axon.MCP.Server        │  ← Docker
  │  Volume: ~/CONTEXT seul │    Projets accessibles UNIQUEMENT
  │  → /CONTEXT             │    via ~/CONTEXT
  └─────────────────────────┘

  ❌ gh copilot ne peut pas appeler Axon
  ❌ VS Code Copilot Chat ne peut pas appeler Axon
  ❌ Projets hors ~/CONTEXT inaccessibles sans copie/symlink
```

### APRÈS

```
  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
  │   VS Code            │  │   axon-cli           │  │   axon-server        │
  │   Copilot Chat       │  │   (mode mission)      │  │   (mode chat)        │
  │   (.vscode/mcp.json) │  │                      │  │                      │
  └──────────┬───────────┘  └──────────┬───────────┘  └──────────┬───────────┘
             │                         │                          │
             │ MCP HTTP                │ MCP stdio                │ MCP stdio
             │ :8000/mcp               │ via proxy Go             │ via proxy Go
             └─────────────────────────┴──────────────────────────┘
                                       │
                                       ▼
                         ┌─────────────────────────┐
                         │  Axon.MCP.Server        │  ← Docker
                         │  FastAPI + Tree-sitter   │
                         │  Volumes:               │
                         │  ~/CONTEXT → /CONTEXT   │  ← projets copiés
                         │  $(pwd)    → /WORKSPACE  │  ← dossier courant ✅
                         │  Analyse 100% locale     │
                         └─────────────────────────┘

  ✅ VS Code Copilot Chat peut appeler les tools Axon via /mcp
  ✅ Tout dossier est analysable sans copie dans ~/CONTEXT
  ✅ Un seul script (axon-start.sh) démarre et indexe tout
```

---

## 5. Diagramme d'architecture complet

```
┌─────────────────────────────────────────────────────────────────────┐
│                        MACHINE LOCALE                               │
│                                                                     │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────────────┐    │
│  │  VS Code     │   │  axon-cli    │   │  axon-server         │    │
│  │  Copilot     │   │  (Go binary) │   │  (Go binary)         │    │
│  │  Chat        │   │  Missions    │   │  Chat interactif     │    │
│  └──────┬───────┘   └──────┬───────┘   └──────────┬───────────┘    │
│         │                  │                       │                │
│         │ HTTP /mcp        │ stdio (MCP)           │ stdio (MCP)    │
│         │                  └───────────────────────┘                │
│         │                            │                              │
│         │                  ┌─────────┴──────────┐                  │
│         │                  │  mcp-axon-proxy    │                  │
│         │                  │  (Go proxy)        │                  │
│         │                  │  SDK Copilot       │──→ api.github.com│
│         │                  │  Personas/Agents   │    (LLM seulement│
│         │                  └─────────┬──────────┘    prompts/réponse│
│         │                            │               zéro code)     │
│         │ HTTP :8000/mcp             │ HTTP :8000/mcp               │
│         └────────────────────────────┘                              │
│                                      │                              │
│                            ┌─────────┴──────────────┐              │
│                            │  axon-mcp-backend      │              │
│                            │  (Docker container)    │              │
│                            │  FastAPI + Tree-sitter  │              │
│                            │  12 tools MCP          │              │
│                            │  ┌───────────────────┐ │              │
│                            │  │ /CONTEXT (volume) │ │              │
│                            │  │ ← ~/CONTEXT       │ │              │
│                            │  ├───────────────────┤ │              │
│                            │  │ /WORKSPACE (vol.) │ │              │
│                            │  │ ← $(pwd) ou       │ │              │
│                            │  │   $AXON_WORKSPACE │ │              │
│                            │  └───────────────────┘ │              │
│                            └────────────────────────┘              │
│                                                                     │
│  🔒 Zéro Egress : le code ne quitte JAMAIS la machine              │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 6. Référence des scripts

| Script | Usage | Description |
|--------|-------|-------------|
| `mcp-axon-proxy/scripts/axon-start.sh` | `cd ~/mon-projet && axon-start` | Démarre, attend, indexe et affiche les instructions |
| `mcp-axon-proxy/scripts/start_mcp_environment.sh` | `./scripts/start_mcp_environment.sh` | Démarre l'env complet + lance le proxy Go en foreground |

| Variable d'environnement | Défaut | Description |
|--------------------------|--------|-------------|
| `AXON_WORKSPACE` | `$(pwd)` | Dossier monté en `/WORKSPACE` dans le container |
| `WORKSPACE_NAME` | `basename(AXON_WORKSPACE)` | Nom utilisé lors de l'indexation dans Axon |
| `AXON_PORT` | `8000` | Port du backend Axon |
| `AXON_BACKEND_URL` | `http://localhost:8000/mcp` | URL utilisée par `axon-cli` et `axon-server` |
