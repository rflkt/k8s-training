# Session 6 : Secrets avances avec External Secrets Operator

> **Objectifs**
> - Comprendre le fonctionnement d'External Secrets Operator (ESO)
> - Configurer un `SecretStore` connecte a GCP Secret Manager via Workload Identity
> - Creer un `ExternalSecret` qui synchronise automatiquement les secrets
> - Observer le rafraichissement automatique des secrets
> - Comparer CSI vs ESO

## Prerequis

- Acces au cluster GKE partage de la formation (`training-cluster` dans le projet `cloud-447406`)
- Namespace `exercices` deja cree
- **External Secrets Operator deja installe** par le formateur (namespace `external-secrets`, cluster-scoped)
- Secrets GCP `training-api-key`, `training-db-password` et `training-oauth-token` deja crees par le formateur dans `cloud-447406` (`training-oauth-token` est utilise par le mini-defi et le bonus 1)
- K8s ServiceAccount `exercices/training-apps` deja lie a la GCP SA `training-apps@cloud-447406.iam.gserviceaccount.com` via Workload Identity (role `roles/secretmanager.secretAccessor`)

> **Convention** : on utilise `<NOM>` comme prefixe personnel (ex: `tim`, `ara`).
> Remplacez `<NOM>` par votre prenom dans toutes les commandes et fichiers YAML pour eviter les collisions avec les autres participants sur ce cluster partage.

Verifiez qu'ESO est en place :

```bash
kubectl -n external-secrets get pods
# Attendez que tous les pods soient Running
```

Verifiez le ServiceAccount partage :

```bash
kubectl -n exercices get sa training-apps -o yaml | grep iam.gke.io
```

---

## Etape 1 : Creer le SecretStore

Le `SecretStore` indique a ESO comment se connecter a GCP Secret Manager. Il reutilise le ServiceAccount `training-apps` deja lie via Workload Identity.

Completez le fichier `starter/secret-store.yaml` (n'oubliez pas de remplacer `<NOM>`) :

1. Ajoutez le provider `gcpsm` avec `projectID: "cloud-447406"`
2. Configurez l'authentification via `workloadIdentity` :
   - `clusterLocation: "europe-west9-b"`
   - `clusterName: "training-cluster"`
   - `serviceAccountRef.name: "training-apps"`

```bash
kubectl apply -f starter/secret-store.yaml
```

Verifiez le statut (il doit indiquer `Valid`) :

```bash
kubectl get secretstore gcp-secret-store-<NOM> -n exercices
```

---

## Etape 2 : Creer l'ExternalSecret

L'`ExternalSecret` decrit quels secrets GCP recuperer et comment les materialiser en `Secret` Kubernetes.

Completez le fichier `starter/external-secret.yaml` (remplacez `<NOM>`) :

1. Definissez le `target.name: api-secrets-<NOM>` avec `creationPolicy: Owner`
2. Ajoutez les entrees `data` :
   - `secretKey: DB_PASSWORD` avec `remoteRef.key: training-db-password`
   - `secretKey: API_KEY` avec `remoteRef.key: training-api-key`

```bash
kubectl apply -f starter/external-secret.yaml
```

---

## Etape 3 : Observer la creation automatique du Secret

ESO cree automatiquement un Secret Kubernetes a partir des secrets GCP :

```bash
# Verifier l'ExternalSecret (status doit etre SecretSynced)
kubectl get externalsecret api-secrets-<NOM> -n exercices

# Le Secret K8s a ete cree automatiquement !
kubectl get secret api-secrets-<NOM> -n exercices

# Voir le contenu (decode)
kubectl get secret api-secrets-<NOM> -n exercices \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
echo
```

---

## Etape 4 : Deployer l'API

```bash
kubectl apply -f starter/api-deployment-eso.yaml
```

Verifiez que les variables d'environnement sont presentes :

```bash
kubectl exec -n exercices deploy/api-<NOM> -- env | grep -E "DB_PASSWORD|API_KEY"
```

---

## Etape 5 : Observer le rafraichissement automatique

> **Note** : seuls les formateurs ont le droit `secretmanager.secretVersionAdder` sur GCP. Le formateur va modifier le secret pendant la session ; observez la propagation cote ESO.

Quand le formateur ajoute une nouvelle version du secret `training-db-password`, attendez le prochain cycle de rafraichissement (1 minute, defini dans `refreshInterval`) puis :

```bash
# Apres ~1 minute
kubectl get secret api-secrets-<NOM> -n exercices \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
echo
```

> **Important** : le Secret Kubernetes est mis a jour automatiquement, mais les variables d'environnement injectees au demarrage du pod NE sont PAS rechargees. Pour que l'application voie la nouvelle valeur, il faut redemarrer le pod :
>
> ```bash
> kubectl rollout restart deploy/api-<NOM> -n exercices
> ```

Pour eviter ce probleme en production : utiliser CSI Secrets Store (rotation des fichiers automatique), un sidecar `reloader`, ou Vault Agent Injector.

---

## Comparaison CSI vs ESO

| Critere | CSI Secrets Store | External Secrets Operator |
|---------|-------------------|--------------------------|
| Stockage | Monte comme fichier | Cree un Secret K8s |
| Rafraichissement | Rotation automatique des fichiers (avec `enableSecretRotation`) | Automatique sur le Secret K8s (configurable) |
| Utilisation | Volume mount | envFrom / env |
| Visibilite | Pas de Secret K8s | Secret K8s cree (visible dans etcd) |
| Rotation cote pod | Recharge le fichier sans redemarrage | Necessite redemarrage du pod pour env vars |
| Multi-provider | Oui | Oui |

**CSI** est preferable quand vous voulez eviter tout stockage dans etcd OU si vos apps relisent un fichier.

**ESO** est preferable quand vos apps lisent les secrets via env vars et que vous tolerez la presence d'un Secret K8s.

---

## Nettoyage

```bash
kubectl delete deploy api-<NOM> -n exercices --ignore-not-found
kubectl delete externalsecret api-secrets-<NOM> -n exercices --ignore-not-found
kubectl delete secretstore gcp-secret-store-<NOM> -n exercices --ignore-not-found
# Le Secret K8s api-secrets-<NOM> est supprime automatiquement (creationPolicy: Owner)
```

---

## Mini-defi

Creez un **second `ExternalSecret`** (par exemple `oauth-secrets-<NOM>`) qui synchronise `training-oauth-token` depuis GCP vers une cle K8s `OAUTH_TOKEN`. Verifiez que les deux Secrets coexistent dans le namespace, chacun synchronise independamment.
