# Session 3 — Exercices Bonus

> Pour ceux qui ont termine le TP principal en avance. Chaque exercice est independant.
> Pensez a remplacer `<NOM>` par votre prenom dans tous les fichiers YAML et commandes.

---

## Bonus 1 : Path-based routing (20 min)

Au lieu de router par domaine, routez par chemin URL. Creez un IngressRoute unique qui gere tout sur un seul host :

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: unified-ingressroute-<NOM>
  namespace: exercices
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`app-<NOM>.training.test`) && PathPrefix(`/api`)
      kind: Rule
      middlewares:
        - name: strip-api-<NOM>
      services:
        - name: api-<NOM>
          port: 80
    - match: Host(`app-<NOM>.training.test`)
      kind: Rule
      services:
        - name: frontend-<NOM>
          port: 80
```

Creez le middleware `strip-api` pour retirer le prefix `/api` :

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: strip-api-<NOM>
  namespace: exercices
spec:
  stripPrefix:
    prefixes:
      - /api
```

Testez :

```bash
# Ajouter l'entree dans /etc/hosts si besoin
# echo "$TRAEFIK_IP app-<NOM>.training.test" | sudo tee -a /etc/hosts

curl -H "Host: app-<NOM>.training.test" http://$TRAEFIK_IP/
curl -H "Host: app-<NOM>.training.test" http://$TRAEFIK_IP/api/health
```

**Question** : Quel est l'avantage d'un routing par chemin vs par domaine ? Quand prefereriez-vous l'un ou l'autre ?

---

## Bonus 2 : Headers de securite (15 min)

Creez un middleware qui ajoute des en-tetes de securite HTTP a toutes les reponses :

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: security-headers-<NOM>
  namespace: exercices
spec:
  headers:
    customResponseHeaders:
      X-Frame-Options: "DENY"
      X-Content-Type-Options: "nosniff"
      X-XSS-Protection: "1; mode=block"
      Referrer-Policy: "strict-origin-when-cross-origin"
    accessControlAllowOriginList:
      - "https://app-<NOM>.training.test"
    accessControlAllowMethods:
      - "GET"
      - "POST"
      - "PUT"
      - "DELETE"
```

Ajoutez-le a l'IngressRoute du frontend et verifiez les en-tetes :

```bash
curl -v -H "Host: frontend-<NOM>.training.test" http://$TRAEFIK_IP/ 2>&1 | grep -i "x-frame\|x-content\|x-xss\|referrer"
```

**Question** : Pourquoi ces headers sont-ils importants en production ? Lequel protege contre le clickjacking ?

---

## Bonus 3 : Weighted round-robin (15 min)

Configurez un canary deployment via le routage pondere de Traefik. Deployez l'API v2 comme service separe :

```bash
# Creer un deployment api-v2
kubectl create deployment api-v2-<NOM> -n exercices \
  --image=europe-west9-docker.pkg.dev/cloud-447406/training/api:v2 \
  --port=8080

# Exposer via un service
kubectl expose deployment api-v2-<NOM> -n exercices --port=80 --target-port=8080
```

Modifiez l'IngressRoute pour envoyer 90% du trafic vers v1 et 10% vers v2 :

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: api-ingressroute-<NOM>
  namespace: exercices
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`api-<NOM>.training.test`)
      kind: Rule
      services:
        - name: api-<NOM>
          port: 80
          weight: 90
        - name: api-v2-<NOM>
          port: 80
          weight: 10
```

Testez la repartition :

```bash
for i in $(seq 1 100); do
  curl -s -H "Host: api-<NOM>.training.test" http://$TRAEFIK_IP/health | grep -o '"version":"[^"]*"'
done | sort | uniq -c
```

Vous devriez voir environ 90 reponses v1 et 10 reponses v2.

**Question** : Comment utiliseriez-vous cette technique pour un rollout progressif en production ? A quel pourcentage passeriez-vous a 100% v2 ?

---

## Bonus 4 : Explorer le dashboard Traefik (10 min)

Ouvrez le dashboard Traefik et explorez :

```bash
kubectl port-forward -n traefik-<NOM> deployment/traefik-<NOM> 9000:9000
# Ouvrez http://localhost:9000/dashboard/
```

Naviguez dans les differentes sections :

1. **Routers** : retrouvez vos IngressRoutes. Combien y en a-t-il ?
2. **Services** : verifiez que chaque service pointe vers les bons pods
3. **Middlewares** : retrouvez votre rate-limit. Quel est l'etat ?
4. **Health** : le dashboard montre-t-il des erreurs ?

**Question** : En quoi le dashboard Traefik est-il utile pour le debugging en production ? Quelles informations manquent par rapport a un vrai outil d'observabilite (Grafana, Datadog) ?
