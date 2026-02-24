# MISSION : Migration de l'application Legacy
1. Analyse comment l'application `~/CONTEXT/app_deja_migree_1` a été migrée. Regarde ses anciens fichiers de config Java et compare-les avec son nouveau fichier `values.yaml` (et ses éventuels appels à la CLI `go-platform`).
2. Identifie les "clés" de traduction (ex: comment l'ancien port Java est déclaré dans le nouveau Helm, comment les variables d'environnement sont passées, comment Vault est activé).
3. Applique cette logique à `~/CONTEXT/app_a_migrer`.
4. Génère le nouveau `values.yaml` (et le script d'appel `go-platform` si nécessaire) dans le dossier de l'application à migrer.
5. EXÉCUTE `helm template mon-app ~/CONTEXT/helm-platform -f ~/CONTEXT/app_a_migrer/values.yaml` via bash pour vérifier que ton fichier values génère un manifest Kubernetes valide. Corrige tes erreurs si la commande échoue.
