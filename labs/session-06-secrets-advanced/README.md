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

Pour eviter ce probleme en production : utiliser CSI Secrets Store (rotation des fichiers automatique), un sidecar `reloader` (annotation `reloader.stakater.com/auto: "true"` sur le Deployment, qui redemarre les pods quand le Secret change), ou Vault Agent Injector.

---

## Etape 6 : Pieges de production a connaitre

ESO est puissant mais comporte des comportements subtils qui font tomber des prods. Cette etape illustre **trois pieges** que vous rencontrerez tot ou tard.

### 6.1 Le piege du `:latest`

Par defaut, ESO recupere `versions/latest` du secret GCP. **Pratique en dev, dangereux en prod** : une mauvaise valeur poussee a l'aide de `gcloud secrets versions add` est immediatement deployee sur **tous** les pods qui synchronisent ce secret. Pas de canary, pas de rollback graduel.

> En production, on pin une version specifique (`remoteRef.version: "3"`) et on bump via Pull Request. Voir Bonus 2.

### 6.2 Le piege du `creationPolicy: Owner` (cascade delete)

Avec `creationPolicy: Owner`, ESO pose un `ownerReference` sur le Secret K8s qu'il cree. Consequence : **supprimer l'ExternalSecret supprime aussi le Secret K8s** (garbage collection Kubernetes). Demo rapide dans votre namespace :

```bash
# 1. Verifiez que le Secret existe
kubectl get secret api-secrets-<NOM> -n exercices

# 2. Supprimez l'ExternalSecret
kubectl delete externalsecret api-secrets-<NOM> -n exercices

# 3. Le Secret a disparu, votre pod va CrashLoopBackOff au prochain restart
kubectl get secret api-secrets-<NOM> -n exercices
# Error from server (NotFound)
```

Recreez l'ExternalSecret pour la suite :

```bash
kubectl apply -f starter/external-secret.yaml
```

> Cas reel : un `helm uninstall` ou un prune Argo CD efface l'ExternalSecret, donc le Secret, donc casse les pods qui en dependent. Utilisez `creationPolicy: Orphan` si vous voulez decoupler le cycle de vie.

### 6.3 Le piege de l'overwrite

Avec `creationPolicy: Owner`, si vous pointez vers un Secret K8s **deja existant** (par exemple `argocd-secret`), ESO va **forcer la reecriture** et perdre toutes les cles qui n'apparaissent pas dans `spec.data`. Bug documente (issue #4548). Voir Bonus 3 pour une demo controlee.

> Regle d'or : un `ExternalSecret` avec `Owner` doit toujours pointer vers un Secret K8s qu'**il cree lui-meme**, jamais vers un Secret prexistant.

---

## Comparaison CSI vs ESO vs Vault

| Critere | CSI Secrets Store | External Secrets Operator | Vault + Vault Agent |
|---------|-------------------|---------------------------|----------------------|
| Stockage K8s | Aucun (fichier monte) | Secret K8s (dans etcd) | Aucun (fichier ou env via sidecar) |
| Rafraichissement | Fichier mis a jour | Secret K8s mis a jour | Renouvellement de bail (lease) |
| Consommation pod | Volume mount | envFrom / env | Volume mount ou env via sidecar |
| Reload du pod | Non (l'app relit le fichier) | Oui si env vars (sauf reloader) | Non (template Vault Agent regenere) |
| Multi-provider | Oui | Oui | Vault uniquement |
| **Secrets dynamiques** | Non | Non | **Oui (creation a la demande de credentials DB, AWS, etc.)** |
| Coute d'exploitation | Bas (DaemonSet) | Bas (controleur) | **Eleve** (HA, unsealing, backups, upgrades) |

Quand choisir quoi :

- **CSI** : quand votre policy de securite interdit tout Secret K8s dans etcd, OU si vos apps relisent un fichier.
- **ESO** : valeur par defaut pour la plupart des cas. Pattern envFrom natif, compatible avec tous les apps existantes.
- **Vault** : quand vous avez besoin de **secrets dynamiques** (un mot de passe DB different par pod, valable 1h, automatiquement revoque). Aucun equivalent natif dans GCP Secret Manager. Mais : exploitation lourde (3-5 pods Raft, strategie de sealing/unsealing, KMS qui scelle vos clefs - si la clef KMS est perdue, Vault est mort).

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
