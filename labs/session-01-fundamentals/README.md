# Session 1 : Fondamentaux Kubernetes

> **Objectifs**
>
> - Se connecter au cluster et explorer les ressources existantes
> - Comprendre la structure d'un manifeste YAML Kubernetes
> - Deployer un Pod et un Deployment
> - Observer le comportement de Kubernetes (auto-healing, replicas)
> - Utiliser les commandes essentielles : `kubectl get`, `describe`, `logs`, `port-forward`

---

## Prerequis

- Acces au cluster GKE configure
- `kubectl` installe et configure
- Les fichiers du dossier `starter/` a portee de main

---

## Etape 1 : Connexion au cluster

Connectez-vous au cluster et verifiez que tout fonctionne :

```bash
# Verifier la connexion au cluster
kubectl cluster-info

# Lister les noeuds du cluster
kubectl get nodes

# Creer le namespace de travail
kubectl create namespace exercices
```

Vous devriez voir les noeuds du cluster avec le statut `Ready`.

---

## Etape 2 : Deployer un Pod nginx

Ouvrez le fichier `starter/nginx-pod.yaml` et completez les `TODO` :

1. Specifiez l'image `nginx:1.25`
2. Ajoutez le port du conteneur `80`

Deployez le Pod :

```bash
kubectl apply -f starter/nginx-pod.yaml
```

Observez le Pod :

```bash
# Lister les pods du namespace
kubectl get pods -n exercices

# Voir les details du pod
kubectl describe pod nginx -n exercices

# Voir les logs du pod
kubectl logs nginx -n exercices
```

Testez l'acces au Pod avec un port-forward :

```bash
kubectl port-forward pod/nginx 8080:80 -n exercices
# Ouvrez http://localhost:8080 dans votre navigateur
```

---

## Etape 3 : Deployer l'API avec un Deployment

Ouvrez le fichier `starter/api-deployment.yaml` et completez les `TODO` :

1. Definissez `replicas: 2`
2. Specifiez l'image : `europe-west9-docker.pkg.dev/cloud-447406/training/api:v1`
3. Ajoutez le port du conteneur `8080`
4. Ajoutez la variable d'environnement `ENVIRONMENT=training`

Deployez :

```bash
kubectl apply -f starter/api-deployment.yaml
```

Observez le Deployment et ses Pods :

```bash
# Voir le deployment
kubectl get deployment api -n exercices

# Voir les pods crees par le deployment
kubectl get pods -n exercices -l app=api

# Voir le ReplicaSet cree automatiquement
kubectl get replicaset -n exercices
```

---

## Etape 4 : Observer l'auto-healing

Supprimez un des pods de l'API et observez ce qui se passe :

```bash
# Notez le nom d'un pod
kubectl get pods -n exercices -l app=api

# Supprimez-le
kubectl delete pod <nom-du-pod> -n exercices

# Observez la recreation automatique
kubectl get pods -n exercices -l app=api -w
```

Kubernetes va automatiquement recreer un nouveau Pod pour maintenir les 2 replicas demandees.

---

## Etape 5 : Port-forward et test de l'API

Testez l'API via port-forward :

```bash
kubectl port-forward deployment/api 9090:8080 -n exercices
# Dans un autre terminal :
curl http://localhost:9090/health
```

---

## Etape 6 : Nettoyage (optionnel)

Si vous souhaitez nettoyer avant de passer a la suite :

```bash
kubectl delete pod nginx -n exercices
kubectl delete deployment api -n exercices
```

---

## Bonus : Scaler le Deployment

Augmentez le nombre de replicas a 4 :

```bash
kubectl scale deployment api --replicas=4 -n exercices

# Observez les nouveaux pods
kubectl get pods -n exercices -l app=api -w
```

Puis redescendez a 2 :

```bash
kubectl scale deployment api --replicas=2 -n exercices
```

---

## Mini-defi

Construisez votre propre image Docker :

1. Creez un `Dockerfile` simple (par exemple avec un serveur HTTP en Python ou Go)
2. Construisez l'image et chargez-la dans `kind` :
   ```bash
   docker build -t mon-app:v1 .
   kind load docker-image mon-app:v1
   ```
3. Ecrivez un manifeste Deployment pour deployer votre image
4. Deployez et testez avec `port-forward`

Cet exercice vous permet de comprendre le cycle complet : code -> image -> deploiement Kubernetes.
