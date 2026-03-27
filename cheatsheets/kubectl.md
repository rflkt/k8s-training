# kubectl -- Aide-memoire

## Navigation & contexte

```bash
# Lister les contextes disponibles
kubectl config get-contexts

# Changer de contexte
kubectl config use-context kind-training

# Contexte courant
kubectl config current-context

# Lister les namespaces
kubectl get namespaces

# Definir le namespace par defaut
kubectl config set-context --current --namespace=mon-namespace
```

## Lister des ressources

```bash
# Pods dans le namespace courant
kubectl get pods

# Pods dans tous les namespaces
kubectl get pods -A

# Pods avec plus de details
kubectl get pods -o wide

# Tous types de ressources
kubectl get all

# Deployments, Services, Ingress
kubectl get deploy,svc,ingress

# Filtrer par label
kubectl get pods -l app=api

# Sortie YAML d'une ressource
kubectl get pod mon-pod -o yaml

# Sortie JSON avec jq
kubectl get pods -o json | jq '.items[].metadata.name'
```

## Creer & appliquer

```bash
# Appliquer un manifeste
kubectl apply -f manifest.yaml

# Appliquer tout un dossier
kubectl apply -f ./manifests/

# Creer un namespace
kubectl create namespace mon-ns

# Lancer un pod rapidement (debug)
kubectl run debug --image=busybox --rm -it -- sh

# Creer un deployment
kubectl create deployment api --image=mon-image:v1 --replicas=3
```

## Deploiements

```bash
# Statut d'un rollout
kubectl rollout status deployment/api

# Historique des rollouts
kubectl rollout history deployment/api

# Rollback au precedent
kubectl rollout undo deployment/api

# Rollback a une revision specifique
kubectl rollout undo deployment/api --to-revision=2

# Mettre a jour l'image
kubectl set image deployment/api api=mon-image:v2

# Scaler
kubectl scale deployment/api --replicas=5
```

## Debug

```bash
# Logs d'un pod
kubectl logs mon-pod

# Logs en continu
kubectl logs -f mon-pod

# Logs d'un conteneur specifique
kubectl logs mon-pod -c mon-conteneur

# Logs des 50 dernières lignes
kubectl logs mon-pod --tail=50

# Decrire une ressource (evenements inclus)
kubectl describe pod mon-pod

# Executer une commande dans un pod
kubectl exec -it mon-pod -- sh

# Copier un fichier depuis/vers un pod
kubectl cp mon-pod:/app/data.json ./data.json
kubectl cp ./config.yaml mon-pod:/app/config.yaml

# Evenements du namespace
kubectl get events --sort-by='.lastTimestamp'

# Port-forward pour acceder a un service
kubectl port-forward svc/api 8080:80
```

## Reseau

```bash
# Lister les services
kubectl get svc

# Details d'un service (endpoints)
kubectl describe svc api

# Lister les endpoints
kubectl get endpoints

# Lister les ingress
kubectl get ingress

# DNS interne -- tester depuis un pod
kubectl exec -it debug -- nslookup api.default.svc.cluster.local

# Port-forward vers un pod
kubectl port-forward pod/mon-pod 3000:3000

# Port-forward vers un service
kubectl port-forward svc/api 8080:80
```

## Secrets & ConfigMaps

```bash
# Creer un secret generique
kubectl create secret generic mon-secret \
  --from-literal=password=supersecret

# Creer un secret depuis un fichier
kubectl create secret generic tls-cert \
  --from-file=cert.pem --from-file=key.pem

# Lister les secrets
kubectl get secrets

# Decoder un secret (base64)
kubectl get secret mon-secret -o jsonpath='{.data.password}' | base64 -d

# Creer une ConfigMap
kubectl create configmap ma-config \
  --from-literal=ENV=production \
  --from-file=config.yaml

# Voir le contenu d'une ConfigMap
kubectl describe configmap ma-config
```

## Nettoyage

```bash
# Supprimer une ressource
kubectl delete pod mon-pod

# Supprimer via un manifeste
kubectl delete -f manifest.yaml

# Supprimer toutes les ressources d'un namespace
kubectl delete all --all -n mon-namespace

# Supprimer un namespace (et tout son contenu)
kubectl delete namespace mon-namespace

# Forcer la suppression d'un pod bloque
kubectl delete pod mon-pod --grace-period=0 --force
```

## Raccourcis utiles

| Ressource | Raccourci |
|-----------|-----------|
| pods | po |
| services | svc |
| deployments | deploy |
| replicasets | rs |
| configmaps | cm |
| namespaces | ns |
| persistentvolumeclaims | pvc |
| ingresses | ing |
| nodes | no |
