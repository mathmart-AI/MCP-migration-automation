MISSION DE DÉPLOIEMENT APPLICATIF (REACT) :
Notre cluster k3d `dev-cluster` est déjà opérationnel avec Traefik comme Ingress Controller par défaut.
1. Analyse le dossier `~/CONTEXT/portfolio` via tes outils Axon.
2. Crée un `Dockerfile` multi-stage optimisé pour cette application Vite/React (stage 1: Node build, stage 2: Nginx alpine) et place-le dans le dossier `portfolio`.
3. Utilise bash pour builder l'image localement : `docker build -t portfolio-app:local ~/CONTEXT/portfolio`.
4. Injecte cette image dans le cluster k3d : `k3d image import portfolio-app:local -c dev-cluster`.
5. Crée un fichier `portfolio-deploy.yaml` contenant : un Deployment (utilisant l'image portfolio-app:local), un Service (port 80), et un Ingress pointant vers le service. L'Ingress doit écouter sur localhost/127.0.0.1.
6. Applique le yaml : `kubectl apply -f portfolio-deploy.yaml`.
7. Attends que le pod soit prêt, puis fais un `curl -s http://127.0.0.1` en bash pour vérifier que le code HTML/React est bien retourné !
