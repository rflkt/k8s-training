# Session 5 : Les Secrets Kubernetes

> **Objectifs**
> - Comprendre pourquoi les mots de passe en dur dans les manifests sont dangereux
> - Utiliser les Secrets natifs Kubernetes
> - Installer le CSI Secrets Store Driver
> - Monter des secrets GCP Secret Manager via CSI

## Prerequis

```bash
kubectl create namespace exercices --dry-run=client -o yaml | kubectl apply -f -
```

---

## Etape 1 : Le probleme -- mot de passe en dur

Deployer le manifest avec le mot de passe en clair :

```bash
kubectl apply -f starter/api-deployment-hardcoded.yaml
```

Maintenant, observez le probleme :

```bash
kubectl get deployment api -n exercices -o yaml | grep DB_PASSWORD
```

Le mot de passe `super-secret-password-123` est visible par **toute personne** ayant acces au cluster ou au depot Git. C'est inacceptable en production.

```bash
kubectl delete deployment api -n exercices
```

---

## Etape 2 : Migrer vers un Secret Kubernetes natif

### 2.1 Creer le Secret

Completez le fichier `starter/db-secret.yaml` :

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

Regardez le fichier `solution/api-deployment-secret.yaml` : il utilise `envFrom` avec une `secretRef` pour injecter automatiquement toutes les cles du Secret comme variables d'environnement.

```bash
kubectl apply -f solution/api-deployment-secret.yaml
```

Verifiez que les variables sont bien injectees :

```bash
kubectl exec -n exercices deploy/api -- env | grep DB_
```

> **Attention** : base64 n'est **pas** du chiffrement ! N'importe qui peut decoder la valeur :
> ```bash
> echo "c3VwZXItc2VjcmV0LXBhc3N3b3JkLTEyMw==" | base64 -d
> ```

```bash
kubectl delete deployment api -n exercices
```

---

## Etape 3 : CSI Secrets Store Driver + GCP Secret Manager

Le CSI Secrets Store Driver permet de monter des secrets d'un provider externe (GCP, AWS, Azure, Vault) directement dans les pods, sans les stocker dans Kubernetes.

### 3.1 Installer le CSI Secrets Store Driver

```bash
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo update

helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true
```

### 3.2 Installer le provider GCP

```bash
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/secrets-store-csi-driver-provider-gcp/main/deploy/provider-gcp-plugin.yaml
```

### 3.3 Creer un secret dans GCP Secret Manager

Si le secret n'existe pas encore :

```bash
echo -n "my-super-api-key" | gcloud secrets create training-api-key \
  --data-file=- \
  --project=cloud-447406
```

### 3.4 Configurer le SecretProviderClass

Completez le fichier `starter/secret-provider-class.yaml` :

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

### 3.5 Deployer l'API avec le volume CSI

Completez le fichier `starter/api-deployment-csi.yaml` :

1. Ajoutez un `volumeMount` sur le conteneur :
   - `name: secrets-store`
   - `mountPath: /mnt/secrets-store`
   - `readOnly: true`

2. Ajoutez un volume CSI :
   ```yaml
   volumes:
     - name: secrets-store
       csi:
         driver: secrets-store.csi.k8s.io
         readOnly: true
         volumeAttributes:
           secretProviderClass: "gcp-secrets"
   ```

```bash
kubectl apply -f starter/api-deployment-csi.yaml
```

### 3.6 Verifier

Le secret est monte comme fichier dans le pod :

```bash
kubectl exec -n exercices deploy/api -- cat /mnt/secrets-store/api-key
```

Le secret n'apparait **nulle part** dans les manifests Kubernetes :

```bash
kubectl get deployment api -n exercices -o yaml | grep -i "api-key"
# Aucun resultat !
```

---

## Recapitulatif

| Methode | Securite | Complexite |
|---------|----------|------------|
| Variable en dur | Tres mauvais | Aucune |
| Secret K8s natif | Moyen (base64) | Faible |
| CSI + GCP Secret Manager | Excellent | Moyenne |

---

## Nettoyage

```bash
kubectl delete -f starter/ -n exercices --ignore-not-found
kubectl delete -f solution/ -n exercices --ignore-not-found
```

---

## Mini-defi

Montez un **deuxieme secret** GCP (`training-db-password`) dans le meme `SecretProviderClass`, a un chemin different (`db-password`). Verifiez que les deux fichiers sont presents dans `/mnt/secrets-store/`.
