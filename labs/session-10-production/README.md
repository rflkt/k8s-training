# Session 10 : Production Readiness

## Objectifs

- Rendre l'application **production-ready** avec des health checks, des limites de ressources et de l'autoscaling
- Configurer des **probes** (liveness, readiness, startup) pour la gestion du cycle de vie des pods
- Définir des **requests et limits** de ressources CPU/mémoire
- Mettre en place un **HorizontalPodAutoscaler** (HPA) et observer le scaling automatique
- Protéger la disponibilité avec un **PodDisruptionBudget** (PDB)
- Sécuriser le réseau avec une **NetworkPolicy**

## Cluster partagé (le cas de la classe)

Cluster partagé — fourni par le formateur. Vous recevez un **namespace dédié**
(`trainee-NN`) et un **kubeconfig de trainee**. Traefik est **déjà installé** par
le formateur ; vous n'avez qu'un accès `edit` sur votre namespace (vous ne pouvez
pas créer de ressources *cluster-scoped* : namespaces, ClusterRoles, IngressClass,
CRDs...).

Les manifests de ce TP **ne fixent plus** `namespace:` en dur. Définissez d'abord
votre namespace, puis appliquez chaque fichier avec `-n $NS` :

```bash
export NS=trainee-01   # remplacez par VOTRE namespace
```

> **Note (continuité avec la Session 9).** En Session 9 vous avez déployé `api`
> et `frontend` dans votre namespace `trainee-NN` via le module Terraform
> `module.app`. Le `api-deployment-probes.yaml` de ce TP porte le **même nom**
> (`api`) : l'appliquer **met à jour / remplace** le Deployment `api` de la
> Session 9 dans votre namespace (en y ajoutant probes + resources). Le
> `frontend` (utilisé pour le test de la NetworkPolicy) doit donc exister dans
> le **même** namespace que `api`.

## Pré-requis

- Votre namespace `trainee-NN` (créé par le formateur) et votre kubeconfig de trainee
- L'API et le frontend déployés dans ce namespace (Session 9)
- **metrics-server** est présent sur le cluster (le HPA fonctionne)
- **NetworkPolicy** : l'application de la policy n'est **réellement appliquée**
  que si le cluster a **Dataplane V2** activé par le formateur. Sans Dataplane V2,
  la policy est **créée mais NON appliquée** : le test "bloqué" ne bloquera pas
  vraiment (voir étape 6).

## Étapes (TP : 1h30)

| # | Étape | Durée |
|---|-------|-------|
| 1 | Probes (liveness/readiness/startup) | 15 min |
| 2 | Requests & limits | 10 min |
| 3 | HorizontalPodAutoscaler | 10 min |
| 4 | Charge + observer le scaling | 15 min |
| 5 | PodDisruptionBudget | 10 min |
| 6 | NetworkPolicy | 20 min |
| — | Mini-défi VPA | 10 min |

### 1. Ajouter les probes (15 min)

Ouvrez `starter/api-deployment-probes.yaml`. Complétez les TODOs pour ajouter :

- **livenessProbe** : vérifie que le processus est vivant (`GET /health`)
- **readinessProbe** : vérifie que l'app est prête à recevoir du trafic (`GET /ready`)
- **startupProbe** : donne du temps au démarrage (`GET /health` avec tolérance élevée)

Appliquez et vérifiez :
```bash
kubectl apply -f api-deployment-probes.yaml -n $NS
kubectl describe pod -n $NS -l app=api | grep -A 5 "Liveness\|Readiness\|Startup"
```

### 2. Définir les ressources (10 min)

Dans le même fichier, complétez les sections `resources` :
- **requests** : ce que le pod demande au minimum (CPU: 100m, mémoire: 128Mi)
- **limits** : le maximum autorisé (CPU: 500m, mémoire: 256Mi)

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

### 4. Générer de la charge et observer le scaling (15 min)

Lancez le script de test de charge :
```bash
chmod +x starter/loadtest.sh
./starter/loadtest.sh
```

Dans un autre terminal, observez le HPA en temps réel :
```bash
kubectl get hpa -n $NS --watch
```

Vous devriez voir le nombre de replicas augmenter progressivement.

### 5. Ajouter un PodDisruptionBudget (10 min)

Ouvrez `starter/api-pdb.yaml`. Le PDB garantit qu'au maximum 1 pod est indisponible lors d'opérations de maintenance (drain, mise à jour du cluster).

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

Testez (l'API est exposée par le Service `api` sur le **port 80**, qui route vers
le port 8080 du conteneur) :
```bash
# Depuis un pod frontend (devrait fonctionner)
# L'image frontend est nginx:1.25-alpine et n'a PAS curl -> on utilise wget (BusyBox)
kubectl exec -n $NS deploy/frontend -- wget -qO- --timeout=3 http://api.$NS.svc.cluster.local/health

# Depuis un pod de test SANS le label frontend (devrait etre bloqué avec Dataplane V2)
kubectl run test-curl --rm -it --image=curlimages/curl -n $NS -- curl -s --max-time 3 http://api.$NS.svc.cluster.local/health
```

> **NetworkPolicy non appliquée sans Dataplane V2.** Si le cluster n'a pas
> Dataplane V2 (activé par le formateur), la policy est bien créée mais **n'est
> pas appliquée** : le second test (depuis `test-curl`) **réussira quand même**.
> Le test "bloqué" ne bloque réellement que sur un cluster avec Dataplane V2.

## Bonus

Installez Prometheus et Grafana avec Helm pour visualiser les métriques :

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace

# Acceder au dashboard Grafana
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
# Login: admin / prom-operator
```

## Mini-défi (10 min)

Créez un **VerticalPodAutoscaler** (VPA) en mode `Off` (recommandation uniquement) pour l'API. Après quelques minutes de charge, consultez les recommandations :

```bash
kubectl get vpa -n $NS -o yaml
```

Comparez les recommandations du VPA avec vos valeurs de requests/limits actuelles. Sont-elles cohérentes ?

> **Pré-requis VPA.** Le mini-défi VPA n'est réalisable que si le **VPA est
> activé sur le cluster par le formateur**. Sans cela, le CRD `VerticalPodAutoscaler`
> est absent et `kubectl get vpa` échoue (`error: the server doesn't have a
> resource type "vpa"`). Le VPA, comme Dataplane V2, est préparé pour la prochaine
> recréation (volontaire) du cluster.
