# Session 10 — Exercices Bonus

> Pour ceux qui ont termine le TP principal en avance. Chaque exercice est independant.

**Cluster partage :** vous travaillez dans votre namespace `trainee-NN` avec un
acces `edit`. Ne mettez pas `"exercices"` en dur. Pour les commandes `kubectl`,
definissez d'abord `NS=trainee-01` (votre namespace), et remplacez `namespace:`
par votre namespace dans les manifests.

```bash
export NS=trainee-01   # remplacez par VOTRE namespace
```

Certains bonus creent des objets **cluster-scoped** ou sont **destructifs sur un
cluster partage** : ils sont marques **"cluster perso uniquement"** et ne doivent
**pas** etre executes tels quels sur le cluster de formation. Les bonus namespaces
(1 et 3) fonctionnent sous l'acces `edit` de votre namespace.

---

## Bonus 1 : HPA avec metriques memoire personnalisees (20 min)

Configurez un **HorizontalPodAutoscaler** basé sur l'utilisation de la memoire au lieu du CPU :

1. Creez un fichier `api-hpa-memory.yaml` :

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa-memory
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

2. Appliquez (dans votre namespace) :

```bash
kubectl apply -f api-hpa-memory.yaml -n $NS
```

3. Verifiez l'HPA :

```bash
kubectl get hpa -n $NS api-hpa-memory --watch
```

4. Generez de la charge **memoire** avec un script custom :

```bash
# Pod de test qui alloue progressivement de la memoire
kubectl run load-memory -it --rm --image=progrium/stress -n $NS \
  -- --vm 1 --vm-bytes 100M --vm-hang 3600 &

# Observez le scaling en temps reel
kubectl get hpa -n $NS --watch
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

> **Cluster perso uniquement.** Cet exercice **cree un namespace** et des
> **ResourceQuota / LimitRange**. Sur le cluster de formation, votre acces `edit`
> **ne permet pas** de creer des namespaces ni des ResourceQuota/LimitRange (ce
> sont des actions du formateur). Faites-le sur votre propre cluster (kind / minikube
> / GKE perso), ou demandez au formateur de pre-creer le namespace et le quota.

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

2. Appliquez (dans votre namespace) :

```bash
kubectl apply -f api-probe-test.yaml -n $NS
```

3. Verifiez que le pod est running :

```bash
kubectl get pods -n $NS -l app=api-test --watch
```

4. Cassez manuellement le health check en modifiant le code ou en creant un endpoint faux :

Alternative (plus simple) : modifiez le deployment pour pointer vers un port inexistant :

```bash
kubectl patch deployment api-probe-test -n $NS \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"api","livenessProbe":{"httpGet":{"port":9999}}}]}}}}'
```

5. Observez le comportement :

```bash
# Le liveness probe echoue
kubectl describe pod -n $NS -l app=api-test | grep -A 5 "Liveness\|Events"

# Apres ~15 secondes (5s * 3 echecs), le pod est kill et redémarre
kubectl get pods -n $NS -l app=api-test -w
```

6. Comptez le nombre de redemarrages :

```bash
kubectl get pods -n $NS -l app=api-test -o json | \
  jq '.items[0].status.containerStatuses[0].restartCount'
```

7. Verifiez les events du pod :

```bash
kubectl describe pod -n $NS -l app=api-test | tail -20
```

8. Restaurez la config correcte :

```bash
kubectl patch deployment api-probe-test -n $NS \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"api","livenessProbe":{"httpGet":{"port":8080}}}]}}}}'
```

**Question** : Comment les probes differentes (liveness, readiness, startup) changent-elles le comportement ? Quand faut-il les utiliser ensemble ? Que se passe-t-il si le liveness threshold est trop bas ?

---

## Bonus 4 : PDB avec disruptions planifiees (15 min)

> **Cluster perso uniquement — NE PAS executer sur le cluster de formation
> partage.** Un `kubectl drain` sur un node est **destructif et global** : il
> evince les pods de **tous** les trainees, pas seulement les votres. De plus,
> votre acces `edit` **ne permet pas** de drainer un node (operation
> cluster-admin). Sur le cluster partage, **limitez-vous au `--dry-run=client`**
> (etape 5) pour voir ce qui serait evince, **sans rien executer reellement**.
> Le drain reel (etapes 6, 8, 10) est reserve a votre propre cluster avec un
> acces cluster-admin.

Testez le **PodDisruptionBudget** en simulant un drain de node :

1. Creez un Deployment avec 3 replicas et un PDB :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-pdb-test
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
spec:
  minAvailable: 2  # Au moins 2 pods doivent toujours etre disponibles
  selector:
    matchLabels:
      app: api-pdb
```

2. Appliquez (dans votre namespace) :

```bash
kubectl apply -f api-pdb-test.yaml -n $NS
```

3. Verifiez les pods et le PDB :

```bash
kubectl get pods -n $NS -l app=api-pdb
kubectl get pdb -n $NS api-pdb -o yaml
```

4. Listez les nodes :

```bash
kubectl get nodes
```

5. Simuler un drain en **dry-run** (sans rien evincer — OK sur le cluster partage) :

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
echo "Node cible (dry-run): $NODE"

# --dry-run=client : montre les pods qui SERAIENT evinces, sans rien executer.
# C'est la SEULE etape a executer sur le cluster de formation partage.
kubectl drain $NODE --ignore-daemonsets --dry-run=client
```

> **STOP — cluster partage.** Les etapes 6 a 10 effectuent un drain **reel**.
> Sur le cluster de formation, **ne les executez PAS** : un drain reel necessite
> un acces **cluster-admin** et **affecte tous les trainees**. Continuez
> uniquement sur **votre propre cluster** (kind / minikube / GKE perso).

6. (Cluster perso) Voyez ce qui se passe si vous tentez vraiment de drainer :

```bash
kubectl drain $NODE --ignore-daemonsets --timeout=30s

# Vous verrez que le drain est bloque parce que le PDB ne permet pas
# de descendre en dessous de 2 pods disponibles
```

7. (Cluster perso) Modifiez le PDB pour permettre plus de disruptions :

```bash
kubectl patch pdb api-pdb -n $NS \
  -p '{"spec":{"maxUnavailable":1}}'
```

8. (Cluster perso) Reetentez le drain (il devrait reussir) :

```bash
kubectl drain $NODE --ignore-daemonsets --timeout=30s
```

9. (Cluster perso) Verifiez que les pods ont migre :

```bash
kubectl get pods -n $NS -l app=api-pdb -o wide
```

10. (Cluster perso) Uncordon le node pour le remettre en service :

```bash
kubectl uncordon $NODE
```

**Question** : Pourquoi les PDBs sont-ils essentiels pour les upgrades de cluster zero-downtime ? Comment configureriez-vous les PDB pour une application critique vs une application non-critique ?
