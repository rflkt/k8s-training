# Session 7 : Introduction a Terraform

> **Objectifs**
> - Installer et configurer Terraform
> - Ecrire une premiere configuration Terraform (bucket GCS)
> - Comprendre le cycle init / plan / apply
> - Explorer le state Terraform
> - Configurer un backend distant (GCS)
> - Creer un module reutilisable

## Prerequis

### Installer Terraform

```bash
# macOS
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Verifier l'installation
terraform version
```

### Authentification GCP

```bash
gcloud auth application-default login
```

---

## Etape 1 : Completer le fichier main.tf

Ouvrez `starter/main.tf` et completez les TODOs :

1. Creez une ressource `google_storage_bucket` nommee `"training"` :
   - `name` = `var.bucket_name`
   - `location` = `var.region`
   - `force_destroy` = `true`

2. Ajoutez le bloc `versioning` avec `enabled = true`

3. Ajoutez les `labels` :
   ```hcl
   labels = {
     environment = "training"
     managed_by  = "terraform"
   }
   ```

4. Ajoutez une `lifecycle_rule` pour supprimer les objets de plus de 30 jours

---

## Etape 2 : Init / Plan / Apply

### 2.1 Initialiser

```bash
cd starter/
terraform init
```

Terraform telecharge le provider Google et initialise le repertoire de travail.

### 2.2 Planifier

```bash
terraform plan -var="project_id=cloud-447406" -var="bucket_name=training-bucket-<VOTRE_NOM>"
```

> **Important** : le nom du bucket doit etre **unique au monde**. Ajoutez votre nom ou un identifiant.

Lisez attentivement le plan. Terraform affiche les ressources qui seront creees.

### 2.3 Appliquer

```bash
terraform apply -var="project_id=cloud-447406" -var="bucket_name=training-bucket-<VOTRE_NOM>"
```

Tapez `yes` pour confirmer. Le bucket est cree.

### 2.4 Verifier

```bash
gsutil ls gs://training-bucket-<VOTRE_NOM>/
```

---

## Etape 3 : Modifier et observer le plan

Ajoutez un label supplementaire dans `main.tf` :

```hcl
labels = {
  environment = "training"
  managed_by  = "terraform"
  session     = "07"
}
```

Relancez le plan :

```bash
terraform plan -var="project_id=cloud-447406" -var="bucket_name=training-bucket-<VOTRE_NOM>"
```

Terraform detecte le changement et propose une modification **in-place** (pas de destruction/recreation).

Appliquez :

```bash
terraform apply -var="project_id=cloud-447406" -var="bucket_name=training-bucket-<VOTRE_NOM>"
```

---

## Etape 4 : Explorer le state

Le state est le fichier ou Terraform stocke l'etat reel des ressources :

```bash
# Lister les ressources dans le state
terraform state list

# Voir le detail d'une ressource
terraform state show google_storage_bucket.training
```

Ouvrez le fichier `terraform.tfstate` dans un editeur. Vous pouvez voir la representation JSON complete de votre bucket.

> **Attention** : ne modifiez **jamais** le fichier tfstate manuellement !

---

## Etape 5 : Configurer un backend distant

En equipe, le state local pose probleme (conflits, perte de donnees). On utilise un backend GCS.

1. Creez un bucket pour le state (via la console GCP ou gsutil) :
   ```bash
   gsutil mb -l europe-west9 gs://training-tfstate-<VOTRE_NOM>/
   ```

2. Copiez `backend.tf.example` vers `backend.tf` et decommentez le contenu :
   ```hcl
   terraform {
     backend "gcs" {
       bucket = "training-tfstate-<VOTRE_NOM>"
       prefix = "terraform/state"
     }
   }
   ```

3. Re-initialisez Terraform (il proposera de migrer le state) :
   ```bash
   terraform init -migrate-state
   ```

4. Verifiez que `terraform.tfstate` local est maintenant vide et que le state est dans GCS.

---

## Etape 6 : Detruire les ressources

```bash
terraform destroy -var="project_id=cloud-447406" -var="bucket_name=training-bucket-<VOTRE_NOM>"
```

Tapez `yes` pour confirmer. Toutes les ressources sont supprimees.

---

## Recapitulatif des commandes

| Commande | Description |
|----------|-------------|
| `terraform init` | Initialise le repertoire, telecharge les providers |
| `terraform plan` | Affiche les changements prevus |
| `terraform apply` | Applique les changements |
| `terraform destroy` | Detruit toutes les ressources |
| `terraform state list` | Liste les ressources gerees |
| `terraform state show` | Affiche le detail d'une ressource |
| `terraform fmt` | Formate les fichiers `.tf` |
| `terraform validate` | Valide la syntaxe |

---

## Nettoyage

```bash
terraform destroy -var="project_id=cloud-447406" -var="bucket_name=training-bucket-<VOTRE_NOM>"
# Supprimer le bucket de state si cree
gsutil rm -r gs://training-tfstate-<VOTRE_NOM>/ 2>/dev/null
```

---

## Mini-defi

Creez un **module reutilisable** pour le bucket GCS (voir `solution/modules/bucket/`). Utilisez ce module dans votre `main.tf` pour creer **deux buckets** avec des noms et des configurations differents en un seul `terraform apply`.
