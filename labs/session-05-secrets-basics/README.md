# Session 5 : Les Secrets Kubernetes

> **Objectifs**
> - Comprendre pourquoi les mots de passe en dur dans les manifests sont dangereux
> - Utiliser les Secrets natifs Kubernetes
> - Monter des secrets GCP Secret Manager dans les pods via le CSI Secrets Store Driver
> - Verifier que les secrets ne fuient jamais dans les manifests

---

## Prerequis

- Acces au cluster GKE partage de la formation (`training-cluster` dans le projet `cloud-447406`)
- Namespace `exercices` deja cree
- CSI Secrets Store Driver + provider GCP **deja installes** par le formateur (cluster-scoped)
- Secret GCP `training-api-key` deja cree par le formateur dans `cloud-447406`
- Workload Identity binding deja configure : K8s ServiceAccount `exercices/training-apps` → GCP SA `training-apps@cloud-447406.iam.gserviceaccount.com` (role `roles/secretmanager.secretAccessor`)

> **Convention** : on utilise `<NOM>` comme prefixe personnel (ex: `tim`, `ara`).
> Remplacez `<NOM>` par votre prenom dans toutes les commandes et fichiers YAML pour eviter les collisions avec les autres participants sur ce cluster partage.

Verifiez que le driver est en place :

```bash
kubectl get csidrivers secrets-store.csi.k8s.io
kubectl -n kube-system get pods -l app=secrets-store-csi-driver
kubectl -n kube-system get pods -l app=csi-secrets-store-provider-gcp
```

---

## Etape 1 : Le probleme -- mot de passe en dur

Deployez le manifest avec le mot de passe en clair (apres avoir remplace `<NOM>`) :

```bash
kubectl apply -f starter/api-deployment-hardcoded.yaml
```

Observez le probleme :

```bash
kubectl get deployment api-<NOM> -n exercices -o yaml | grep DB_PASSWORD
```

Le mot de passe `super-secret-password-123` est visible par **toute personne** ayant acces au cluster ou au depot Git. C'est inacceptable en production.

```bash
kubectl delete -f starter/api-deployment-hardcoded.yaml
```

---

## Etape 2 : Migrer vers un Secret Kubernetes natif

### 2.1 Creer le Secret

Completez le fichier `starter/db-secret.yaml` (n'oubliez pas de remplacer `<NOM>`) :

1. Ajoutez `type: Opaque`
2. Ajoutez une section `data` avec les cles suivantes :
   - `DB_PASSWORD` : la valeur `super-secret-password-123` encodee en base64
   - `DB_USER` : la valeur `api-user` encodee en base64

Pour encoder en base64 :

```bash
echo -n "super-secret-password-123" | base64
# Resultat : c3VwZXItc2VjcmV0LXBhc3N3b3JkLTEyMw==

echo -n "api-user" | base64
# Resultat : YXBpLXVzZXI=
```

Appliquez le Secret :

```bash
kubectl apply -f starter/db-secret.yaml
```

### 2.2 Deployer l'API avec le Secret

Regardez le fichier `solution/api-deployment-secret.yaml` : il utilise `envFrom` avec une `secretRef` pour injecter automatiquement toutes les cles du Secret comme variables d'environnement. Adaptez le nom (`api-<NOM>`, `db-credentials-<NOM>`) puis appliquez :

```bash
# Avec sed pour substituer <NOM> a la volee (ou editez le fichier)
sed "s/api-tim/api-<NOM>/g; s/db-credentials-tim/db-credentials-<NOM>/g" \
  solution/api-deployment-secret.yaml | kubectl apply -f -
```

Verifiez que les variables sont bien injectees :

```bash
kubectl exec -n exercices deploy/api-<NOM> -- env | grep DB_
```

> **Attention** : base64 n'est **pas** du chiffrement ! N'importe qui peut decoder la valeur :
> ```bash
> echo "c3VwZXItc2VjcmV0LXBhc3N3b3JkLTEyMw==" | base64 -d
> ```
> Le Secret est aussi visible avec `kubectl get secret db-credentials-<NOM> -o yaml` et apparait en clair dans `etcd` (cote control-plane).

```bash
kubectl delete deployment api-<NOM> -n exercices
kubectl delete secret db-credentials-<NOM> -n exercices
```

---

## Etape 3 : CSI Secrets Store Driver + GCP Secret Manager

Le CSI Secrets Store Driver monte des secrets d'un provider externe (GCP, AWS, Azure, Vault) directement dans les pods comme **fichiers**, sans creer de K8s Secret intermediaire.

### 3.1 Configurer le SecretProviderClass

Completez le fichier `starter/secret-provider-class.yaml` (remplacez `<NOM>`) :

1. Definissez `provider: gcp`
2. Ajoutez la section `parameters` avec le chemin vers le secret GCP :
   ```yaml
   parameters:
     secrets: |
       - resourceName: "projects/cloud-447406/secrets/training-api-key/versions/latest"
         path: "api-key"
   ```

```bash
kubectl apply -f starter/secret-provider-class.yaml
```

### 3.2 Deployer l'API avec le volume CSI

Completez le fichier `starter/api-deployment-csi.yaml` (remplacez `<NOM>`) :

1. Ajoutez un `volumeMount` sur le conteneur :
   - `name: secrets-store`
   - `mountPath: /mnt/secrets-store`
   - `readOnly: true`

2. Ajoutez le volume CSI :
   ```yaml
   volumes:
     - name: secrets-store
       csi:
         driver: secrets-store.csi.k8s.io
         readOnly: true
         volumeAttributes:
           secretProviderClass: "gcp-secrets-<NOM>"
   ```

> **Note** : le manifest definit deja `serviceAccountName: training-apps`. C'est essentiel — c'est ce ServiceAccount qui possede la binding Workload Identity vers la GCP SA autorisee a lire Secret Manager. Sans ca : `permission denied`.

```bash
kubectl apply -f starter/api-deployment-csi.yaml
```

### 3.3 Verifier

Le secret est monte comme fichier dans le pod :

```bash
kubectl exec -n exercices deploy/api-<NOM> -- cat /mnt/secrets-store/api-key
```

Le secret n'apparait **nulle part** dans les manifests Kubernetes :

```bash
kubectl get deployment api-<NOM> -n exercices -o yaml | grep -i "api-key"
# Aucun resultat !
```

---

## Recapitulatif

| Methode | Securite | Visible via... |
|---------|----------|----------------|
| Variable en dur | Tres mauvais | `kubectl get deploy -o yaml`, git, image Docker, logs CI |
| Secret K8s natif | Moyen (base64) | `kubectl get secret -o yaml`, etcd |
| CSI + GCP Secret Manager | Excellent | Fichier dans le pod uniquement, audit dans GCP Logs |

---

## Nettoyage

```bash
kubectl delete deployment api-<NOM> -n exercices --ignore-not-found
kubectl delete secret db-credentials-<NOM> -n exercices --ignore-not-found
kubectl delete secretproviderclass gcp-secrets-<NOM> -n exercices --ignore-not-found
```

---

## Mini-defi

Montez un **deuxieme secret** GCP (`training-db-password`, deja cree par le formateur) dans le meme `SecretProviderClass`, a un chemin different (`db-password`). Verifiez que les deux fichiers sont presents dans `/mnt/secrets-store/`.
