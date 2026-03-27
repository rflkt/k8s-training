# Session 3 : Ingress et Traefik

> **Objectifs**
>
> - Comprendre le role d'un Ingress Controller dans Kubernetes
> - Installer et configurer Traefik via Helm
> - Creer des IngressRoutes (CRD Traefik) pour exposer les services
> - Ajouter un middleware de rate-limiting
> - Tester le routage par nom de domaine avec `curl`

---

## Prerequis

- Sessions 1 et 2 terminees (API + frontend deployes avec leurs Services)
- Helm installe (`brew install helm` ou equivalent)
- Namespace `exercices` avec l'API et le frontend en cours d'execution

Verifiez que vos services sont en place :

```bash
kubectl get deployments,svc -n exercices
```

---

## Etape 1 : Installer Traefik

Ajoutez le repo Helm de Traefik et installez-le :

```bash
# Ajouter le repo Helm
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Installer Traefik avec les valeurs pre-configurees
helm install traefik traefik/traefik \
  -n traefik --create-namespace \
  -f starter/traefik-values.yaml
```

Verifiez l'installation :

```bash
# Verifier que les pods Traefik sont en cours d'execution
kubectl get pods -n traefik

# Verifier le service LoadBalancer
kubectl get svc -n traefik

# Acceder au dashboard Traefik
kubectl port-forward -n traefik svc/traefik 8080:80
# Ouvrez http://localhost:8080/dashboard/ dans votre navigateur
```

---

## Etape 2 : Creer un IngressRoute pour l'API

Ouvrez le fichier `starter/api-ingressroute.yaml` et completez les `TODO` :

1. Ajoutez une route avec `match: Host(`api.training.local`)`
2. Specifiez `kind: Rule`
3. Ajoutez le service `api` sur le port `80`

Deployez l'IngressRoute :

```bash
kubectl apply -f starter/api-ingressroute.yaml
```

Verifiez que l'IngressRoute est creee :

```bash
kubectl get ingressroute -n exercices
```

---

## Etape 3 : Tester avec curl

Recuperez l'IP du LoadBalancer Traefik :

```bash
export TRAEFIK_IP=$(kubectl get svc traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo $TRAEFIK_IP
```

Testez l'acces a l'API via Traefik :

```bash
curl -H "Host: api.training.local" http://$TRAEFIK_IP/health
```

Si vous travaillez en local, ajoutez l'entree dans `/etc/hosts` :

```bash
echo "$TRAEFIK_IP api.training.local frontend.training.local" | sudo tee -a /etc/hosts
```

Puis testez directement :

```bash
curl http://api.training.local/health
```

---

## Etape 4 : Creer un IngressRoute pour le frontend

Creez un fichier `frontend-ingressroute.yaml` sur le modele de l'API, avec :

- `match: Host(`frontend.training.local`)`
- Service `frontend` sur le port `80`

Deployez et testez :

```bash
kubectl apply -f frontend-ingressroute.yaml
curl -H "Host: frontend.training.local" http://$TRAEFIK_IP/
```

---

## Etape 5 : Ajouter le rate-limiting

Ouvrez le fichier `starter/middleware-ratelimit.yaml` et completez les `TODO` :

1. Definissez `average: 100`
2. Definissez `burst: 200`

Deployez le middleware :

```bash
kubectl apply -f starter/middleware-ratelimit.yaml
```

Modifiez l'IngressRoute de l'API pour utiliser le middleware :

```yaml
routes:
  - match: Host(`api.training.local`)
    kind: Rule
    middlewares:
      - name: ratelimit
    services:
      - name: api
        port: 80
```

Appliquez la modification et testez :

```bash
kubectl apply -f starter/api-ingressroute.yaml

# Testez avec des requetes rapides
for i in $(seq 1 250); do
  curl -s -o /dev/null -w "%{http_code}\n" -H "Host: api.training.local" http://$TRAEFIK_IP/health
done
```

Vous devriez voir des reponses `429 Too Many Requests` au-dela du burst.

---

## Bonus : Middleware stripPrefix

Creez un middleware `stripPrefix` pour retirer un prefixe d'URL :

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: strip-api-prefix
  namespace: exercices
spec:
  stripPrefix:
    prefixes:
      - /backend
```

Ajoutez une route qui matche `Host(`api.training.local`) && PathPrefix(`/backend`)` avec ce middleware. Cela permet d'acceder a l'API via `http://api.training.local/backend/health` tout en retirant `/backend` avant de transmettre la requete au service.

---

## Mini-defi

Configurez un routage avance avec Traefik :

1. Creez un middleware `basicAuth` pour proteger l'acces au dashboard ou a un service
2. Creez un middleware `headers` pour ajouter des en-tetes de securite (CORS, HSTS)
3. Combinez plusieurs middlewares sur une meme IngressRoute (chain)

Consultez la documentation Traefik pour les middlewares disponibles : https://doc.traefik.io/traefik/middlewares/overview/
