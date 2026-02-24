# MISSION : Audit de la Helm Platform
1. Analyse le chart Helm situé dans `~/CONTEXT/helm-platform`.
2. Identifie comment fonctionne le dossier `templates/library`. Quels sont les helpers ou renderers principaux disponibles pour les microservices ?
3. Trouve comment les secrets Vault sont injectés (cherche les annotations ou les variables spécifiques dans les values).
4. Trouve comment Tekton est branché sur ce chart.
5. Génère un fichier `PLATFORM_CHEATSHEET.md` à la racine résumant les variables obligatoires du `values.yaml` pour déployer un simple Springboot sur cette plateforme.
