# Session 2 : Services et reseau

> **Objectifs**
>
> - Comprendre le role des Services Kubernetes (ClusterIP)
> - Decouvrir le DNS interne du cluster (`<service>.<namespace>.svc.cluster.local`)
> - Deployer un frontend nginx avec reverse proxy vers l'API
> - Utiliser un ConfigMap pour configurer nginx
> - Effectuer un rolling update et un rollback

---

## Prerequis

- Session 1 terminee (ou deployer les solutions de la session 1)
- Namespace `exercices` cree

---

## Etape 1 : Deployer l'API et son Service

Deployez l'API (si ce n'est pas deja fait) :

```bash
kubectl apply -f starter/api-deployment.yaml
```

Ouvrez le fichier `starter/api-service.yaml` et completez les `TODO` :

1. Ajoutez le selector `app: api`
2. Configurez le port : `port: 80`, `targetPort: 8080`

Deployez le Service :

```bash
kubectl apply -f starter/api-service.yaml
```

Verifiez que le Service est cree :

```bash
kubectl get svc -n exercices
kubectl describe svc api -n exercices
```

---

## Etape 2 : Tester le DNS interne

Lancez un pod temporaire pour tester la resolution DNS :

```bash
kubectl run -n exercices debug --rm -it --image=busybox -- sh
```

Dans le shell du pod :

```sh
# Tester la resolution DNS
nslookup api.exercices.svc.cluster.local

# Tester l'acces a l'API
wget -qO- http://api.exercices.svc.cluster.local:80/health
```

Notez que le Service `api` sur le port 80 redirige vers le port 8080 des pods.

---

## Etape 3 : Configurer le reverse proxy nginx

Ouvrez le fichier `starter/frontend-configmap.yaml` et completez le `TODO` :

Ajoutez un bloc `location /api/` qui proxy les requetes vers l'API :

```nginx
location /api/ {
    proxy_pass http://api.exercices.svc.cluster.local:80/;
}
```

Deployez le ConfigMap :

```bash
kubectl apply -f starter/frontend-configmap.yaml
```

---

## Etape 4 : Deployer le frontend HTML personnalise

Le fichier `starter/frontend-html-configmap.yaml` contient une page HTML personnalisee qui affiche le statut de l'API, le hostname du pod et la version de l'application. Cette page se rafraichit automatiquement toutes les 5 secondes — vous verrez le hostname changer quand les requetes sont reparties entre les pods.

Deployez le ConfigMap HTML :

```bash
kubectl apply -f starter/frontend-html-configmap.yaml
```

> **Note** : Le Deployment du frontend monte ce ConfigMap dans `/usr/share/nginx/html/index.html` pour remplacer la page par defaut de nginx.

---

## Etape 5 : Deployer le frontend

Ouvrez le fichier `starter/frontend-deployment.yaml` et completez les `TODO` :

1. Specifiez l'image `nginx:1.25-alpine`
2. Ajoutez le port du conteneur `80`
3. Referencez le ConfigMap `frontend-nginx-config`

Deployez le frontend et son Service :

```bash
kubectl apply -f starter/frontend-deployment.yaml
kubectl apply -f starter/frontend-service.yaml
```

---

## Etape 6 : Tester le frontend

Utilisez un port-forward pour acceder au frontend :

```bash
kubectl port-forward svc/frontend 8080:80 -n exercices
```

Ouvrez http://localhost:8080 dans votre navigateur. Vous devriez voir la page personnalisee avec le statut de l'API, le hostname du pod et la version.

Testez aussi en ligne de commande :

```bash
# Page d'accueil personnalisee
curl http://localhost:8080/

# Requete proxifiee vers l'API
curl http://localhost:8080/api/health
```

La requete `/api/health` est proxifiee par nginx vers le Service `api` via le DNS interne du cluster.

---

## Etape 7 : Rolling update

Mettez a jour l'image de l'API vers la v2 :

```bash
kubectl set image deployment/api api=europe-west9-docker.pkg.dev/cloud-447406/training/api:v2 -n exercices
```

Observez le rolling update en temps reel :

```bash
kubectl rollout status deployment/api -n exercices
kubectl get pods -n exercices -l app=api -w
```

Verifiez la nouvelle version :

```bash
kubectl port-forward svc/api 9090:80 -n exercices
curl http://localhost:9090/health
```

> **Astuce** : Gardez le navigateur ouvert sur http://localhost:8080 pendant le rolling update. Le badge de version passera de `v1` a `v2` et vous verrez les hostnames changer au fur et a mesure que les nouveaux pods remplacent les anciens.

---

## Etape 8 : Rollback

Revenez a la version precedente :

```bash
# Voir l'historique des deployments
kubectl rollout history deployment/api -n exercices

# Rollback vers la version precedente
kubectl rollout undo deployment/api -n exercices

# Verifier le statut
kubectl rollout status deployment/api -n exercices
```

---

## Bonus : ConfigMap avance

Modifiez le ConfigMap pour ajouter des en-tetes de proxy supplementaires :

```nginx
location /api/ {
    proxy_pass http://api.exercices.svc.cluster.local:80/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Apres la mise a jour du ConfigMap, redemarrez les pods du frontend :

```bash
kubectl rollout restart deployment/frontend -n exercices
```

---

## Mini-defi

Creez un deuxieme backend (par exemple `api-v2`) avec une configuration differente et configurez nginx pour router les requetes :

- `/api/v1/` -> service `api` (v1)
- `/api/v2/` -> service `api-v2` (v2)

Cela vous permet de comprendre le pattern de routing au niveau du reverse proxy, un concept fondamental avant d'aborder les Ingress dans la session suivante.
