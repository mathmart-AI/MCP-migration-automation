MISSION DE DÉPLOIEMENT ET VALIDATION KUBERNETES :
1. Crée un nouveau dossier nommé `k3d_observability_test` dans le répertoire courant et déplaces-y tes opérations.
2. Rédige un script bash robuste pour créer un cluster k3d nommé `dev-cluster` (assure-toi de détruire l'ancien s'il existe déjà).
3. EXÉCUTE ce script via tes outils bash. Attends que le cluster soit prêt.
4. Vérifie que le cluster répond en exécutant `kubectl get nodes`.
5. Génère les manifests Helm (Chart et values.yaml) pour installer `kube-prometheus-stack` de manière allégée.
6. EXÉCUTE l'installation Helm sur le cluster k3d que tu viens de créer.
7. Vérifie que les pods de Prometheus sont en cours de création via `kubectl get pods`.
Si à n'importe quelle étape une exécution échoue, corrige ton script et recommence.
