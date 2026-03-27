# Session 6 : Secrets avances avec External Secrets Operator

> **Objectifs**
> - Installer External Secrets Operator (ESO)
> - Configurer un SecretStore connecte a GCP Secret Manager
> - Creer un ExternalSecret qui synchronise automatiquement les secrets
> - Observer le rafraichissement automatique des secrets
> - Comparer CSI vs ESO

## Prerequis

```bash
kubectl create namespace exercices --dry-run=client -o yaml | kubectl apply -f -
```

---

## Etape 1 : Installer External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true
```

Verifiez que les pods ESO sont en cours d'execution :

```bash
kubectl get pods -n external-secrets
```

Attendez que tous les pods soient `Running` avant de continuer.

---

## Etape 2 : Configurer le ServiceAccount pour Workload Identity

ESO a besoin d'un ServiceAccount Kubernetes lie a un ServiceAccount GCP via Workload Identity :

```bash
kubectl create serviceaccount eso-service-account -n exercices

gcloud iam service-accounts add-iam-policy-binding \
  eso-sa@cloud-447406.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:cloud-447406.svc.id.goog[exercices/eso-service-account]"

kubectl annotate serviceaccount eso-service-account \
  -n exercices \
  iam.gke.io/gcp-service-account=eso-sa@cloud-447406.iam.gserviceaccount.com
```

---

## Etape 3 : Creer le SecretStore

Completez le fichier `starter/secret-store.yaml` :

1. Ajoutez le provider `gcpsm` avec le `projectID`
2. Configurez l'authentification via `workloadIdentity` :
   - `clusterLocation` : `europe-west9`
   - `clusterName` : `training-cluster`
   - `serviceAccountRef.name` : `eso-service-account`

```bash
kubectl apply -f starter/secret-store.yaml
```

Verifiez le statut :

```bash
kubectl get secretstore -n exercices
```

Le statut doit indiquer `Valid`.

---

## Etape 4 : Creer l'ExternalSecret

Completez le fichier `starter/external-secret.yaml` :

1. Definissez le `target.name` : `api-secrets`
2. Definissez `creationPolicy: Owner`
3. Ajoutez les entrees `data` :
   - `secretKey: DB_PASSWORD` avec `remoteRef.key: training-db-password`
   - `secretKey: API_KEY` avec `remoteRef.key: training-api-key`

```bash
kubectl apply -f starter/external-secret.yaml
```

---

## Etape 5 : Observer la creation automatique du Secret

ESO cree automatiquement un Secret Kubernetes a partir des secrets GCP :

```bash
# Verifier l'ExternalSecret
kubectl get externalsecret -n exercices

# Le Secret K8s a ete cree automatiquement !
kubectl get secret api-secrets -n exercices

# Voir le contenu (decode)
kubectl get secret api-secrets -n exercices -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
```

---

## Etape 6 : Deployer l'API

```bash
kubectl apply -f starter/api-deployment-eso.yaml
```

Verifiez que les variables d'environnement sont presentes :

```bash
kubectl exec -n exercices deploy/api -- env | grep -E "DB_PASSWORD|API_KEY"
```

---

## Etape 7 : Observer le rafraichissement automatique

Modifiez le secret dans GCP :

```bash
echo -n "new-password-456" | gcloud secrets versions add training-db-password --data-file=-
```

Attendez le prochain cycle de rafraichissement (1 minute defini dans `refreshInterval`) :

```bash
# Apres ~1 minute
kubectl get secret api-secrets -n exercices -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
# Devrait afficher : new-password-456
```

> **Note** : le pod doit etre redemarre pour prendre en compte les nouvelles valeurs des variables d'environnement. Le Secret Kubernetes est mis a jour automatiquement, mais les variables d'environnement sont lues au demarrage du conteneur.

---

## Comparaison CSI vs ESO

| Critere | CSI Secrets Store | External Secrets Operator |
|---------|-------------------|--------------------------|
| Stockage | Monte comme fichier | Cree un Secret K8s |
| Rafraichissement | A la rotation du pod | Automatique (configurable) |
| Utilisation | Volume mount | envFrom / env |
| Visibilite | Pas de Secret K8s | Secret K8s cree |
| Complexite | Moyenne | Moyenne |
| Multi-provider | Oui | Oui |

**CSI** est preferable quand vous voulez eviter tout stockage dans etcd (Secret K8s).

**ESO** est preferable quand vos applications lisent les secrets via des variables d'environnement et que vous voulez un rafraichissement automatique.

---

## Nettoyage

```bash
kubectl delete -f starter/ -n exercices --ignore-not-found
kubectl delete -f solution/ -n exercices --ignore-not-found
kubectl delete serviceaccount eso-service-account -n exercices --ignore-not-found
```

---

## Mini-defi

Creez un `ClusterSecretStore` (au lieu d'un `SecretStore`) qui peut etre utilise par **tous les namespaces** du cluster. Deployez une copie de l'API dans un nouveau namespace `exercices-2` qui utilise le meme `ClusterSecretStore` pour acceder aux secrets GCP.
