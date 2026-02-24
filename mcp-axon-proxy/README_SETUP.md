# 🧠 MCP Axon — Zero Egress Architecture

> **A Plug & Play MCP server for GitHub Copilot**, combining a Go proxy (Copilot SDK) with a Python backend (FastAPI) — all running locally, with **zero data egress** to external services.

---

## 📐 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        VS Code + GitHub Copilot                 │
│                                                                 │
│  settings.json → points to ./mcp-axon-proxy binary as MCP       │
└────────────────────────────┬────────────────────────────────────┘
                             │ stdio (JSON-RPC)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Go Proxy  (mcp-axon-proxy)                      │
│                                                                 │
│  • Compiled Go binary                                           │
│  • Uses github.com/github/copilot-sdk/go                        │
│  • Registers tools dynamically from the Python backend          │
│  • Relays tool calls via HTTP to http://localhost:8000/mcp      │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTP (localhost:8000)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│         Python Backend  (Docker container)                       │
│                                                                 │
│  • FastAPI + Uvicorn on port 8000                               │
│  • MCP protocol tools: code parsing, analysis, graph building   │
│  • tree-sitter, GitPython, code extractors                      │
│  • No LLM calls — pure code intelligence ("Dumb Backend")       │
└─────────────────────────────────────────────────────────────────┘
```

**Principe clé** : Le binaire Go est le seul point d'entrée pour Copilot. Il communique avec le backend Python via `localhost` uniquement. Aucune donnée ne quitte votre machine — tout reste en local.

---

## ✅ Prérequis

| Outil          | Version minimale | Installation                                                        |
|----------------|------------------|---------------------------------------------------------------------|
| **Docker Desktop** | 4.x+         | [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/) |
| **Go**         | 1.21+            | [go.dev/dl](https://go.dev/dl/)                                     |
| **VS Code**    | Latest           | [code.visualstudio.com](https://code.visualstudio.com/)             |
| **GitHub Copilot** | Extension    | Marketplace VS Code (nécessite un plan Enterprise/Business)         |

> [!NOTE]
> Sur **Windows**, utilisez WSL2 (Ubuntu). Docker Desktop doit être configuré pour utiliser le backend WSL2.
> Toutes les commandes ci-dessous s'exécutent dans un terminal WSL.

---

## 🚀 Démarrage Rapide

### 1. Cloner le dépôt

```bash
# Clonez les deux projets côte à côte :
# parent/
# ├── Axon.MCP.Server/    ← Backend Python
# └── mcp-axon-proxy/     ← Proxy Go
```

### 2. Lancer l'environnement

```bash
cd mcp-axon-proxy/
./start_mcp_environment.sh
```

C'est tout ! Le script va automatiquement :

1. ✅ Vérifier que Go et Docker sont installés
2. 🔨 Compiler le binaire Go
3. 🐳 Construire l'image Docker du backend Python
4. ⏳ Attendre que le backend soit prêt (health check)
5. 🚀 Lancer le proxy Go (connecté au Copilot SDK)

> [!TIP]
> Le premier lancement peut prendre 2-3 minutes (build Docker). Les lancements suivants seront quasi instantanés grâce au cache Docker.

### 3. Arrêter l'environnement

Appuyez sur `Ctrl+C` dans le terminal. Le script arrête et nettoie automatiquement le conteneur Docker.

---

## ⚙️ Configuration VS Code

Pour que GitHub Copilot utilise votre serveur MCP local, modifiez votre `settings.json` VS Code :

### Ouvrir les settings

`Ctrl+Shift+P` → `Preferences: Open User Settings (JSON)`

### Ajouter la configuration MCP

```jsonc
{
  // ... vos autres settings ...

  "github.copilot.chat.mcpServers": {
    "axon-mcp": {
      "command": "/chemin/absolu/vers/mcp-axon-proxy/mcp-axon-proxy",
      "args": [],
      "env": {
        "AXON_BACKEND_URL": "http://localhost:8000/mcp"
      }
    }
  }
}
```

> [!IMPORTANT]
> Remplacez `/chemin/absolu/vers/` par le chemin réel vers votre binaire compilé.
> Sur WSL, le chemin ressemblera à : `/home/votre-user/projects/mcp-axon-proxy/mcp-axon-proxy`

---

## 💬 Exemples de Prompts Copilot

Une fois l'environnement lancé et VS Code configuré, ouvrez le chat GitHub Copilot et utilisez les outils MCP :

### Analyse de code Java

```
@workspace Analyse ce fichier Java src/main/java/com/example/OrderService.java
et utilise les outils MCP pour comprendre le graphe d'appels de toutes les méthodes.
Génère un diagramme Mermaid des dépendances.
```

### Migration technologique

```
@workspace J'ai un projet .NET dans le dossier /home/user/legacy-app/.
Utilise les outils MCP pour parser tous les fichiers C#,
extraire l'architecture des services, et génère un plan de migration
vers une architecture microservices avec des charts Helm Kubernetes.
```

### Documentation automatique

```
@workspace Analyse la documentation Atlassian dans le dossier ./docs/confluence-export/
et le code source dans ./src/. Utilise les outils MCP pour croiser
les spécifications avec l'implémentation réelle.
Génère un rapport d'écart (gap analysis) au format Markdown.
```

### Analyse d'impact

```
@workspace Je dois modifier la classe UserRepository.
Utilise les outils MCP pour trouver tous les appelants
de cette classe dans le projet, et génère un rapport d'impact
listant tous les fichiers et tests affectés.
```

---

## 🔧 Configuration Avancée

### Variables d'environnement

| Variable             | Défaut                         | Description                                  |
|----------------------|--------------------------------|----------------------------------------------|
| `AXON_BACKEND_URL`   | `http://localhost:8000/mcp`    | URL du backend Python                        |
| `AXON_API_KEY`       | *(vide)*                       | Clé API si l'auth est activée sur le backend |

### Personnaliser le port

Éditez les variables en haut du script `start_mcp_environment.sh` :

```bash
AXON_PORT=9000  # Changer le port du backend
```

Puis dans `settings.json`, mettez à jour `AXON_BACKEND_URL` en conséquence.

---

## 🐛 Dépannage

| Problème | Solution |
|----------|----------|
| `Docker daemon is not running` | Lancez Docker Desktop, attendez qu'il soit prêt |
| `Python backend did not become healthy` | Vérifiez les logs : `docker logs axon-mcp-backend` |
| `Failed to register dynamic tools` | Le backend n'est pas prêt. Relancez le script |
| `go build` échoue | Vérifiez votre version Go (`go version`) et les dépendances (`go mod tidy`) |
| Copilot ne détecte pas le MCP | Vérifiez le chemin absolu dans `settings.json` et redémarrez VS Code |

---

## 📁 Structure des projets

```
parent/
├── Axon.MCP.Server/               ← Backend Python ("Dumb Backend")
│   ├── Dockerfile                  ← Image Docker optimisée
│   ├── requirements.txt            ← Dépendances Python purgées
│   └── src/
│       ├── api/main.py             ← Point d'entrée FastAPI
│       └── mcp_server/             ← Implémentation MCP protocol
│
└── mcp-axon-proxy/                 ← Proxy Go (Copilot SDK)
    ├── start_mcp_environment.sh    ← 🚀 Script de démarrage Plug & Play
    ├── README_SETUP.md             ← Ce fichier
    ├── cmd/server/main.go          ← Point d'entrée Go
    └── internal/tools/             ← Enregistrement dynamique des outils
```
