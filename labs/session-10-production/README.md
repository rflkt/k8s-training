# Session 10 : Production Readiness

## Objectifs

- Rendre l'application **production-ready** avec des health checks, des limites de ressources et de l'autoscaling
- Configurer des **probes** (liveness, readiness, startup) pour la gestion du cycle de vie des pods
- Definir des **requests et limits** de ressources CPU/memoire
- Mettre en place un **HorizontalPodAutoscaler** (HPA) et observer le scaling automatique
- Proteger la disponibilite avec un **PodDisruptionBudget** (PDB)
- Securiser le reseau avec une **NetworkPolicy**

## Pre-requis

- Cluster GKE fonctionnel avec le namespace `exercices`
- L'API deployee (session precedente)
- Metrics Server installe (inclus par defaut sur GKE)

## Etapes

### 1. Ajouter les probes

Ouvrez `starter/api-deployment-probes.yaml`. Completez les TODOs pour ajouter :

- **livenessProbe** : verifie que le processus est vivant (`GET /health`)
- **readinessProbe** : verifie que l'app est prete a recevoir du trafic (`GET /ready`)
- **startupProbe** : donne du temps au demarrage (`GET /health` avec tolerance elevee)

Appliquez et verifiez :
```bash
kubectl apply -f api-deployment-probes.yaml
kubectl describe pod -n exercices -l app=api | grep -A 5 "Liveness\|Readiness\|Startup"
```

### 2. Definir les ressources

Dans le meme fichier, completez les sections `resources` :
- **requests** : ce que le pod demande au minimum (CPU: 100m, memoire: 128Mi)
- **limits** : le maximum autorise (CPU: 500m, memoire: 256Mi)

```bash
kubectl top pods -n exercices
```

### 3. Configurer le HPA

Ouvrez `starter/api-hpa.yaml`. Configurez un HPA qui :
- Cible le Deployment `api`
- Scale entre 2 et 5 replicas
- Vise une utilisation CPU de 70%

```bash
kubectl apply -f api-hpa.yaml
kubectl get hpa -n exercices
```

### 4. Generer de la charge et observer le scaling

Lancez le script de test de charge :
```bash
chmod +x starter/loadtest.sh
./starter/loadtest.sh
```

Dans un autre terminal, observez le HPA en temps reel :
```bash
kubectl get hpa -n exercices --watch
```

Vous devriez voir le nombre de replicas augmenter progressivement.

### 5. Ajouter un PodDisruptionBudget

Ouvrez `starter/api-pdb.yaml`. Le PDB garantit qu'au maximum 1 pod est indisponible lors d'operations de maintenance (drain, mise a jour du cluster).

```bash
kubectl apply -f api-pdb.yaml
kubectl get pdb -n exercices
```

### 6. Ajouter une NetworkPolicy

Ouvrez `starter/network-policy.yaml`. La NetworkPolicy doit :
- S'appliquer aux pods avec le label `app: api`
- Autoriser uniquement le trafic entrant depuis les pods `app: frontend` sur le port 8080
- Bloquer tout autre trafic entrant

```bash
kubectl apply -f network-policy.yaml
kubectl get networkpolicy -n exercices
```

Testez :
```bash
# Depuis un pod frontend (devrait fonctionner)
kubectl exec -n exercices deploy/frontend -- curl -s http://api.exercices.svc.cluster.local/health

# Depuis un pod de test (devrait etre bloque)
kubectl run test-curl --rm -it --image=curlimages/curl -n exercices -- curl -s --max-time 3 http://api.exercices.svc.cluster.local/health
```

## Bonus

Installez Prometheus et Grafana avec Helm pour visualiser les metriques :

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace

# Acceder au dashboard Grafana
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
# Login: admin / prom-operator
```

## Mini-defi

Creez un **VerticalPodAutoscaler** (VPA) en mode `Off` (recommandation uniquement) pour l'API. Apres quelques minutes de charge, consultez les recommandations :

```bash
kubectl get vpa -n exercices -o yaml
```

Comparez les recommandations du VPA avec vos valeurs de requests/limits actuelles. Sont-elles coherentes ?
