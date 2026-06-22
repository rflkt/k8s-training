# Session 10 : Production Readiness

## Objectifs

- Rendre l'application **production-ready** avec des health checks, des limites de ressources et de l'autoscaling
- Configurer des **probes** (liveness, readiness, startup) pour la gestion du cycle de vie des pods
- Definir des **requests et limits** de ressources CPU/memoire
- Mettre en place un **HorizontalPodAutoscaler** (HPA) et observer le scaling automatique
- Proteger la disponibilite avec un **PodDisruptionBudget** (PDB)
- Securiser le reseau avec une **NetworkPolicy**

## Cluster partage (le cas de la classe)

Cluster partage — fourni par le formateur. Vous recevez un **namespace dedie**
(`trainee-NN`) et un **kubeconfig de trainee**. Traefik est **deja installe** par
le formateur ; vous n'avez qu'un acces `edit` sur votre namespace (vous ne pouvez
pas creer de ressources *cluster-scoped* : namespaces, ClusterRoles, IngressClass,
CRDs...).

Les manifests de ce TP **ne fixent plus** `namespace:` en dur. Definissez d'abord
votre namespace, puis appliquez chaque fichier avec `-n $NS` :

```bash
export NS=trainee-01   # remplacez par VOTRE namespace
```

> **Note (continuite avec la Session 9).** En Session 9 vous avez deploye `api`
> et `frontend` dans votre namespace `trainee-NN` via le module Terraform
> `module.app`. Le `api-deployment-probes.yaml` de ce TP porte le **meme nom**
> (`api`) : l'appliquer **met a jour / remplace** le Deployment `api` de la
> Session 9 dans votre namespace (en y ajoutant probes + resources). Le
> `frontend` (utilise pour le test de la NetworkPolicy) doit donc exister dans
> le **meme** namespace que `api`.

## Pre-requis

- Votre namespace `trainee-NN` (cree par le formateur) et votre kubeconfig de trainee
- L'API et le frontend deployes dans ce namespace (Session 9)
- **metrics-server** est present sur le cluster (le HPA fonctionne)
- **NetworkPolicy** : l'application de la policy n'est **reellement appliquee**
  que si le cluster a **Dataplane V2** active par le formateur. Sans Dataplane V2,
  la policy est **creee mais NON appliquee** : le test "bloque" ne bloquera pas
  vraiment (voir etape 6).

## Etapes (TP : 1h30)

| # | Etape | Duree |
|---|-------|-------|
| 1 | Probes (liveness/readiness/startup) | 15 min |
| 2 | Requests & limits | 10 min |
| 3 | HorizontalPodAutoscaler | 10 min |
| 4 | Charge + observer le scaling | 15 min |
| 5 | PodDisruptionBudget | 10 min |
| 6 | NetworkPolicy | 20 min |
| — | Mini-defi VPA | 10 min |

### 1. Ajouter les probes (15 min)

Ouvrez `starter/api-deployment-probes.yaml`. Completez les TODOs pour ajouter :

- **livenessProbe** : verifie que le processus est vivant (`GET /health`)
- **readinessProbe** : verifie que l'app est prete a recevoir du trafic (`GET /ready`)
- **startupProbe** : donne du temps au demarrage (`GET /health` avec tolerance elevee)

Appliquez et verifiez :
```bash
kubectl apply -f api-deployment-probes.yaml -n $NS
kubectl describe pod -n $NS -l app=api | grep -A 5 "Liveness\|Readiness\|Startup"
```

### 2. Definir les ressources (10 min)

Dans le meme fichier, completez les sections `resources` :
- **requests** : ce que le pod demande au minimum (CPU: 100m, memoire: 128Mi)
- **limits** : le maximum autorise (CPU: 500m, memoire: 256Mi)

```bash
kubectl top pods -n $NS
```

### 3. Configurer le HPA (10 min)

Ouvrez `starter/api-hpa.yaml`. Configurez un HPA qui :
- Cible le Deployment `api`
- Scale entre 2 et 5 replicas
- Vise une utilisation CPU de 70%

```bash
kubectl apply -f api-hpa.yaml -n $NS
kubectl get hpa -n $NS
```

### 4. Generer de la charge et observer le scaling (15 min)

Lancez le script de test de charge :
```bash
chmod +x starter/loadtest.sh
./starter/loadtest.sh
```

Dans un autre terminal, observez le HPA en temps reel :
```bash
kubectl get hpa -n $NS --watch
```

Vous devriez voir le nombre de replicas augmenter progressivement.

### 5. Ajouter un PodDisruptionBudget (10 min)

Ouvrez `starter/api-pdb.yaml`. Le PDB garantit qu'au maximum 1 pod est indisponible lors d'operations de maintenance (drain, mise a jour du cluster).

```bash
kubectl apply -f api-pdb.yaml -n $NS
kubectl get pdb -n $NS
```

### 6. Ajouter une NetworkPolicy (20 min)

Ouvrez `starter/network-policy.yaml`. La NetworkPolicy doit :
- S'appliquer aux pods avec le label `app: api`
- Autoriser uniquement le trafic entrant depuis les pods `app: frontend` sur le port 8080
- Bloquer tout autre trafic entrant

```bash
kubectl apply -f network-policy.yaml -n $NS
kubectl get networkpolicy -n $NS
```

Testez (l'API est expose par le Service `api` sur le **port 80**, qui route vers
le port 8080 du conteneur) :
```bash
# Depuis un pod frontend (devrait fonctionner)
# L'image frontend est nginx:1.25-alpine et n'a PAS curl -> on utilise wget (BusyBox)
kubectl exec -n $NS deploy/frontend -- wget -qO- --timeout=3 http://api.$NS.svc.cluster.local/health

# Depuis un pod de test SANS le label frontend (devrait etre bloque avec Dataplane V2)
kubectl run test-curl --rm -it --image=curlimages/curl -n $NS -- curl -s --max-time 3 http://api.$NS.svc.cluster.local/health
```

> **NetworkPolicy non appliquee sans Dataplane V2.** Si le cluster n'a pas
> Dataplane V2 (active par le formateur), la policy est bien creee mais **n'est
> pas appliquee** : le second test (depuis `test-curl`) **reussira quand meme**.
> Le test "bloque" ne bloque reellement que sur un cluster avec Dataplane V2.

## Bonus

Installez Prometheus et Grafana avec Helm pour visualiser les metriques :

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace

# Acceder au dashboard Grafana
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
# Login: admin / prom-operator
```

## Mini-defi (10 min)

Creez un **VerticalPodAutoscaler** (VPA) en mode `Off` (recommandation uniquement) pour l'API. Apres quelques minutes de charge, consultez les recommandations :

```bash
kubectl get vpa -n $NS -o yaml
```

Comparez les recommandations du VPA avec vos valeurs de requests/limits actuelles. Sont-elles coherentes ?

> **Pre-requis VPA.** Le mini-defi VPA n'est realisable que si le **VPA est
> active sur le cluster par le formateur**. Sans cela, le CRD `VerticalPodAutoscaler`
> est absent et `kubectl get vpa` echoue (`error: the server doesn't have a
> resource type "vpa"`). Le VPA, comme Dataplane V2, est prepare pour la prochaine
> recreation (volontaire) du cluster.
