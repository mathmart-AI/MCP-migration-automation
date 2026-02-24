# 🎯 Mission : Cluster K3d Local avec Monitoring Prometheus/Grafana

## Contexte

Nous avons besoin d'un environnement Kubernetes local pour le développement et les tests.
L'objectif est de créer un **script Bash complet et prêt à l'emploi** qui met en place toute la stack.

## Objectifs

### 1. Cluster K3d

- Créer un cluster k3d nommé `axon-dev` avec **1 server + 2 agents**
- Exposer les ports :
  - `80` → Ingress HTTP
  - `443` → Ingress HTTPS
  - `8080` → NodePort pour les services applicatifs
- Utiliser Traefik comme Ingress Controller (intégré dans k3s)
- Configurer le cluster pour permettre le déploiement de LoadBalancer services

### 2. Monitoring — Prometheus + Grafana

- Installer `kube-prometheus-stack` via Helm dans le namespace `monitoring`
- Configurer les valeurs Helm suivantes :
  - **Grafana** : admin password = `axon-admin`, exposé via Ingress sur `grafana.localhost`
  - **Prometheus** : rétention de 7 jours, stockage de 10Gi en PVC
  - **Alertmanager** : activé avec une configuration minimale
  - **Node Exporter** : activé
  - **kube-state-metrics** : activé
- Ajouter les ServiceMonitors pour scraper les métriques du cluster

### 3. Dashboard Grafana pré-configuré

- Ajouter un dashboard JSON pour le monitoring du cluster :
  - CPU / Memory usage par node
  - Pod count par namespace
  - Request rate des Ingress

### 4. Script de validation

- À la fin du script principal, inclure une section de validation automatique :
  - Vérifier que tous les pods dans `monitoring` sont en état `Running`
  - Vérifier que Grafana répond sur `http://grafana.localhost`
  - Vérifier que Prometheus répond sur `http://localhost:9090`
  - Afficher un résumé coloré (✓ / ✗) de chaque vérification

## Livrables attendus

1. **`setup_k3d_cluster.sh`** — Script Bash principal (idempotent, relançable)
2. **`values-prometheus.yaml`** — Fichier de valeurs Helm personnalisées
3. **`grafana-dashboard-cluster.json`** — Dashboard Grafana pré-configuré

## Contraintes

- Le script doit fonctionner sur macOS (avec Docker Desktop) et Linux
- Utiliser `helm repo add` / `helm upgrade --install` pour l'idempotence
- Toutes les sorties doivent être colorées et lisibles dans un terminal
- Le script doit vérifier les prérequis (`docker`, `k3d`, `kubectl`, `helm`) au démarrage
