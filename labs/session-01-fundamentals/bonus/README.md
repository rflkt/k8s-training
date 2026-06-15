# Session 1 — Exercices Bonus

> Pour ceux qui ont termine le TP principal en avance. Chaque exercice est independant.

---

## Bonus 1 : Pod multi-conteneurs avec pattern Sidecar (20 min)

Apprenez le pattern sidecar en creant un pod avec deux conteneurs : l'application principale et un conteneur auxiliaire.

1. Creez un fichier `sidecar-pod.yaml` avec deux conteneurs :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: api-with-logger-<NOM>
  namespace: exercices
spec:
  containers:
    - name: api
      image: europe-west9-docker.pkg.dev/cloud-447406/training/api:v1
      ports:
        - containerPort: 8080
    - name: file-logger
      image: busybox:1.35
      command: 
        - /bin/sh
        - -c
        - while true; do echo "API est en cours d'execution ($(date))" >> /logs/activity.log; sleep 5; done
      volumeMounts:
        - name: shared-logs
          mountPath: /logs
  volumes:
    - name: shared-logs
      emptyDir: {}
```

2. Appliquez le manifest :

```bash
kubectl apply -f sidecar-pod.yaml
```

3. Verifiez que les deux conteneurs tournent :

```bash
kubectl get pods -n exercices -o wide
kubectl describe pod api-with-logger-<NOM> -n exercices
```

4. Consultez les logs des deux conteneurs :

```bash
# Logs de l'API
kubectl logs api-with-logger-<NOM> -n exercices -c api

# Logs du logger
kubectl logs api-with-logger-<NOM> -n exercices -c file-logger
```

5. Accedez au fichier de log partage via exec :

```bash
kubectl exec api-with-logger-<NOM> -n exercices -c api -- cat /logs/activity.log
```

**Question** : Quel est l'interet du pattern sidecar ? Donnez 3 cas d'usage reels (logging, monitoring, transformation de donnees, etc.).

---

## Bonus 2 : Exploration des ressources du cluster (15 min)

Decouvrez les informations detaillees du cluster et les limites de ressources :

1. Verifiez l'espace disque disponible sur les noeuds :

```bash
# Voir les informations des noeuds
kubectl get nodes -o wide

# Voir les details d'un noeud (capacite, ressources allouees)
kubectl describe node <NODE-NAME>

# Voir l'utilisation des ressources en temps reel
kubectl top nodes
```

2. Consultez les limites de ressources des pods :

```bash
# Voir l'utilisation des pods
kubectl top pods -n exercices

# Decrire l'API pour voir les ressources demandees/limitees
kubectl describe deployment api -n exercices | grep -A 10 "Limits\|Requests"
```

3. Explorez les informations du cluster :

```bash
# Informations detaillees du cluster
kubectl cluster-info

# Version de Kubernetes
kubectl version

# Plugins disponibles
kubectl api-resources | head -20
```

**Question** : Quelle est la difference entre les `Requests` (ressources demandees) et les `Limits` (limites maximales) ? Pourquoi est-ce important de les definir ?

---

## Bonus 3 : Construction et deploiement d'une image personnalisee (20 min)

Creez votre propre image Docker et deployez-la dans Kubernetes.

1. Creez un dossier temporaire et un `Dockerfile` simple :

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY app.py .

EXPOSE 5000

CMD ["python", "app.py"]
```

2. Creez le fichier `app.py` :

```python
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import os

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        response = {
            "message": "Hello from my custom app",
            "version": "1.0",
            "nom": os.getenv("NOM", "unknown")
        }
        self.wfile.write(json.dumps(response).encode())

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 5000), Handler)
    print("Server running on port 5000...")
    server.serve_forever()
```

3. Construisez l'image et chargez-la dans le cluster kind :

```bash
docker build -t mon-app:<NOM>-v1 .
kind load docker-image mon-app:<NOM>-v1 --name training
```

4. Creez un Deployment avec votre image :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mon-app-<NOM>
  namespace: exercices
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mon-app
  template:
    metadata:
      labels:
        app: mon-app
    spec:
      containers:
        - name: app
          image: mon-app:<NOM>-v1
          imagePullPolicy: Never
          ports:
            - containerPort: 5000
          env:
            - name: NOM
              value: <NOM>
```

5. Deployez et testez :

```bash
kubectl apply -f mon-app-deployment.yaml

# Attendez que le pod soit Ready
kubectl get pods -n exercices -l app=mon-app -w

# Testez avec port-forward
kubectl port-forward deployment/mon-app-<NOM> 5000:5000 -n exercices

# Dans un autre terminal
curl http://localhost:5000
```

**Question** : Quels sont les avantages d'utiliser `imagePullPolicy: Never` dans un environnement de developpement local ? Pourquoi ne pas l'utiliser en production ?

---

## Bonus 4 : Gestion du cycle de vie des Pods (15 min)

Explorez les mecanismes de gestion du cycle de vie : initialisation, readiness, liveness.

1. Creez un pod avec un init container qui simule une initialisation :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-avec-init-<NOM>
  namespace: exercices
spec:
  initContainers:
    - name: wait-for-setup
      image: busybox:1.35
      command: 
        - /bin/sh
        - -c
        - echo "Initialisation en cours..."; sleep 3; echo "Initialisation complete"
  containers:
    - name: app
      image: nginx:1.25
      ports:
        - containerPort: 80
```

2. Appliquez et observez :

```bash
kubectl apply -f pod-avec-init-<NOM>.yaml

# Observez les phases du pod
kubectl get pods -n exercices pod-avec-init-<NOM> -w

# Verifiez les init containers
kubectl describe pod pod-avec-init-<NOM> -n exercices | grep -A 5 "Init Containers"

# Consultez les logs de l'init container
kubectl logs pod-avec-init-<NOM> -n exercices -c wait-for-setup
```

3. Explorez ensuite les probes de sante (`livenessProbe`, `readinessProbe`) :

```bash
# Dans la Session 1, ces concepts ne sont pas detailles,
# mais vous pouvez explorer leur usage dans les Deployments existants
kubectl get deployment api -n exercices -o yaml | grep -A 10 "Probe"
```

**Question** : Quelle est la difference entre un init container et les liveness/readiness probes ? Dans quel ordre s'executent-ils au demarrage d'un pod ?

