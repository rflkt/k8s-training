# Session 10 — Exercices Bonus

> Pour ceux qui ont termine le TP principal en avance. Chaque exercice est independant.

---

## Bonus 1 : HPA avec metriques memoire personnalisees (20 min)

Configurez un **HorizontalPodAutoscaler** basé sur l'utilisation de la memoire au lieu du CPU :

1. Creez un fichier `api-hpa-memory.yaml` :

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa-memory
  namespace: exercices
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 2
  maxReplicas: 6
  metrics:
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 60  # Scale si memoire > 60%
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 60
      policies:
        - type: Percent
          value: 50  # Reduit de 50% a la fois (plus conservateur)
          periodSeconds: 15
    scaleUp:
      stabilizationWindowSeconds: 0  # Augmente immediatement
      policies:
        - type: Percent
          value: 100  # Double le nombre de replicas
          periodSeconds: 15
```

2. Appliquez :

```bash
kubectl apply -f api-hpa-memory.yaml
```

3. Verifiez l'HPA :

```bash
kubectl get hpa -n exercices api-hpa-memory --watch
```

4. Generez de la charge **memoire** avec un script custom :

```bash
# Pod de test qui alloue progressivement de la memoire
kubectl run load-memory -it --rm --image=progrium/stress -n exercices \
  -- --vm 1 --vm-bytes 100M --vm-hang 3600 &

# Observez le scaling en temps reel
kubectl get hpa -n exercices --watch
```

5. Arrêtez le test et observez le scale down :

```bash
# Kill le pod de charge
pkill -f "load-memory"
```

6. Comparez avec l'HPA basé CPU. Quel est plus reactif ? Lequel est plus adapte a votre application ?

**Question** : Pourquoi certaines applications scaling mieux sur CPU et d'autres sur memoire ? Comment choisiriez-vous la metrique appropriee ?

---

## Bonus 2 : ResourceQuota et LimitRange par namespace (15 min)

Protegez les ressources du cluster en definissant des **quotas et limites par namespace** :

1. Creez un fichier `namespace-resources.yaml` :

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: exercices-limited
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: exercices-quota
  namespace: exercices-limited
spec:
  hard:
    requests.cpu: "4"       # Max 4 CPU pour tout le namespace
    requests.memory: "4Gi"  # Max 4GB de memoire pour tout le namespace
    limits.cpu: "8"         # Max 8 CPU limites
    limits.memory: "8Gi"    # Max 8GB limites
    pods: "10"              # Max 10 pods
    persistentvolumeclaims: "2"
  scopeSelector:
    matchExpressions:
      - operator: In
        scopeName: PriorityClass
        values: ["default"]
---
apiVersion: v1
kind: LimitRange
metadata:
  name: exercices-limits
  namespace: exercices-limited
spec:
  limits:
    - max:
        cpu: "2"
        memory: "1Gi"
      min:
        cpu: "50m"
        memory: "64Mi"
      default:
        cpu: "500m"
        memory: "256Mi"
      defaultRequest:
        cpu: "100m"
        memory: "128Mi"
      type: Container
    - max:
        cpu: "4"
        memory: "2Gi"
      min:
        cpu: "50m"
        memory: "64Mi"
      type: Pod
```

2. Appliquez :

```bash
kubectl apply -f namespace-resources.yaml
```

3. Verifiez les quotas :

```bash
kubectl get resourcequota -n exercices-limited -o yaml
kubectl describe resourcequota exercices-quota -n exercices-limited
```

4. Testez le quota en creant trop de pods :

```bash
# Creer un Deployment qui utilise 3 CPU (depasse le quota)
kubectl create deployment high-cpu -n exercices-limited \
  --image=stress:latest \
  --replicas=3

kubectl set resources deployment high-cpu -n exercices-limited \
  --requests=cpu=1500m,memory=512Mi \
  --limits=cpu=2000m,memory=512Mi

# Verifiez que le DeploymentSet est bloque
kubectl describe deployment high-cpu -n exercices-limited
```

5. Verifiez la consommation :

```bash
kubectl describe quota exercices-quota -n exercices-limited
```

6. Testez le LimitRange en creant un pod sans ressources :

```bash
# Pod auto-reçoit les limites par defaut du LimitRange
kubectl run test-limits -n exercices-limited \
  --image=nginx:latest \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl describe pod test-limits -n exercices-limited | grep -A 5 "Limits\|Requests"
```

**Question** : Comment les ResourceQuotas et LimitRanges vous aident-ils a eviter les surcharges du cluster ? Quand commenceriez-vous a utiliser les deux ensemble ?

---

## Bonus 3 : Simulation de panne - Liveness probe failure (20 min)

Testez le comportement de Kubernetes quand un **liveness probe echoue** :

1. Deployez une version modifiee de l'API qui peut se mettre en "erreur" :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-probe-test
  namespace: exercices
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api-test
  template:
    metadata:
      labels:
        app: api-test
    spec:
      containers:
        - name: api
          image: europe-west9-docker.pkg.dev/cloud-447406/training/api:v1
          ports:
            - containerPort: 8080
          livenessProbe:
            httpGet:
              path: /health  # Endpoint qui peut devenir "unhealthy"
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 3  # Apres 3 echecs, kill le pod
            timeoutSeconds: 2
          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 3
            periodSeconds: 3
            failureThreshold: 2
```

2. Appliquez :

```bash
kubectl apply -f api-probe-test.yaml
```

3. Verifiez que le pod est running :

```bash
kubectl get pods -n exercices -l app=api-test --watch
```

4. Cassez manuellement le health check en modifiant le code ou en creant un endpoint faux :

Alternative (plus simple) : modifiez le deployment pour pointer vers un port inexistant :

```bash
kubectl patch deployment api-probe-test -n exercices \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"api","livenessProbe":{"httpGet":{"port":9999}}}]}}}}'
```

5. Observez le comportement :

```bash
# Le liveness probe echoue
kubectl describe pod -n exercices -l app=api-test | grep -A 5 "Liveness\|Events"

# Apres ~15 secondes (5s * 3 echecs), le pod est kill et redémarre
kubectl get pods -n exercices -l app=api-test -w
```

6. Comptez le nombre de redemarrages :

```bash
kubectl get pods -n exercices -l app=api-test -o json | \
  jq '.items[0].status.containerStatuses[0].restartCount'
```

7. Verifiez les events du pod :

```bash
kubectl describe pod -n exercices -l app=api-test | tail -20
```

8. Restaurez la config correcte :

```bash
kubectl patch deployment api-probe-test -n exercices \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"api","livenessProbe":{"httpGet":{"port":8080}}}]}}}}'
```

**Question** : Comment les probes differentes (liveness, readiness, startup) changent-elles le comportement ? Quand faut-il les utiliser ensemble ? Que se passe-t-il si le liveness threshold est trop bas ?

---

## Bonus 4 : PDB avec disruptions planifiees (15 min)

Testez le **PodDisruptionBudget** en simulant un drain de node :

1. Creez un Deployment avec 3 replicas et un PDB :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-pdb-test
  namespace: exercices
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-pdb
  template:
    metadata:
      labels:
        app: api-pdb
    spec:
      containers:
        - name: api
          image: europe-west9-docker.pkg.dev/cloud-447406/training/api:v1
          ports:
            - containerPort: 8080
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-pdb
  namespace: exercices
spec:
  minAvailable: 2  # Au moins 2 pods doivent toujours etre disponibles
  selector:
    matchLabels:
      app: api-pdb
```

2. Appliquez :

```bash
kubectl apply -f api-pdb-test.yaml
```

3. Verifiez les pods et le PDB :

```bash
kubectl get pods -n exercices -l app=api-pdb
kubectl get pdb -n exercices api-pdb -o yaml
```

4. Listez les nodes :

```bash
kubectl get nodes
```

5. Drainer un node (cela evacue les pods) :

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
echo "Draining node: $NODE"

# Avec --dry-run pour verifier d'abord
kubectl drain $NODE --ignore-daemonsets --dry-run=client
```

6. Voyez ce qui se passe si vous tentez vraiment de drainer :

```bash
kubectl drain $NODE --ignore-daemonsets --timeout=30s

# Vous verrez que le drain est bloque parce que le PDB ne permet pas
# de descendre en dessous de 2 pods disponibles
```

7. Modifiez le PDB pour permettre plus de disruptions :

```bash
kubectl patch pdb api-pdb -n exercices \
  -p '{"spec":{"maxUnavailable":1}}'
```

8. Reetentez le drain (il devrait reussir) :

```bash
kubectl drain $NODE --ignore-daemonsets --timeout=30s
```

9. Verifiez que les pods ont migre :

```bash
kubectl get pods -n exercices -l app=api-pdb -o wide
```

10. Uncordon le node pour le remettre en service :

```bash
kubectl uncordon $NODE
```

**Question** : Pourquoi les PDBs sont-ils essentiels pour les upgrades de cluster zero-downtime ? Comment configureriez-vous les PDB pour une application critique vs une application non-critique ?
