# Session 2 — Exercices Bonus

> Pour ceux qui ont termine le TP principal en avance. Chaque exercice est independant.

---

## Bonus 1 : Blue-Green Deployment manuel (20 min)

Simulez un deploiement blue-green sans downtime :

1. Creez un second Deployment `api-green` avec l'image `api:v2` et le label `version: green` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-green
  namespace: exercices
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
      version: green
  template:
    metadata:
      labels:
        app: api
        version: green
    spec:
      containers:
        - name: api
          image: europe-west9-docker.pkg.dev/cloud-447406/training/api:v2
          ports:
            - containerPort: 8080
```

2. Le Service `api` existant utilise le selector `app: api` — il route donc vers les pods v1 ET v2.

3. Modifiez le Service pour cibler uniquement `version: green` :

```bash
kubectl patch svc api -n exercices -p '{"spec":{"selector":{"app":"api","version":"green"}}}'
```

4. Verifiez que tout le trafic va vers v2 (checkez le `/health` plusieurs fois)

5. Si tout est OK, supprimez l'ancien Deployment. Sinon, revenez en arriere en patchant le selector vers `version: blue`.

**Question** : Quels sont les avantages et inconvenients par rapport au rolling update natif de Kubernetes ?

---

## Bonus 2 : Observabilite des Services (15 min)

Explorez les mecanismes d'observation de Kubernetes :

```bash
# 1. Voir les endpoints du service (quels pods recoivent du trafic ?)
kubectl get endpoints api -n exercices -o yaml

# 2. Voir les evenements du namespace (historique des actions K8s)
kubectl get events -n exercices --sort-by=.metadata.creationTimestamp

# 3. Voir les logs de tous les pods API en meme temps
kubectl logs -l app=api -n exercices --all-containers -f

# 4. Decrire un service pour voir sa configuration complete
kubectl describe svc api -n exercices

# 5. Observer la repartition du trafic en temps reel
for i in $(seq 1 20); do
  kubectl exec -n exercices deploy/frontend -- wget -qO- http://api.exercices.svc.cluster.local:80/health 2>/dev/null | grep hostname
done
```

**Question** : Combien de pods differents repondent ? Le load balancing est-il parfaitement reparti ?

---

## Bonus 3 : Multi-port Service et nommage (10 min)

Modifiez le Service `api` pour exposer plusieurs ports nommes :

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: exercices
spec:
  selector:
    app: api
  ports:
    - name: http
      port: 80
      targetPort: 8080
    - name: metrics
      port: 9090
      targetPort: 8080
```

Testez l'acces via les deux ports :

```bash
kubectl exec -n exercices deploy/frontend -- wget -qO- http://api.exercices.svc.cluster.local:80/health
kubectl exec -n exercices deploy/frontend -- wget -qO- http://api.exercices.svc.cluster.local:9090/health
```

**Question** : Dans quel cas reel aurait-on besoin de plusieurs ports sur un Service ? (pensez : metriques Prometheus, gRPC + HTTP, admin vs public)
