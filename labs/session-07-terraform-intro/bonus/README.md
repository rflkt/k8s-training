# Session 7 — Exercices Bonus

> Pour ceux qui ont termine le TP principal en avance. Chaque exercice est independant.

---

## Bonus 1 : Validation et formatage Terraform (15 min)

Etablissez un workflow de validation avant d'appliquer des changements :

1. Creez un nouveau fichier `main.tf` avec une erreur volontaire (ex: fermeture de bloc manquante) :

```hcl
resource "google_storage_bucket" "test" {
  name     = "test-bucket-bonus"
  location = "EU"
  # Bloc fermeture manquante
```

2. Validez la syntaxe :

```bash
cd starter/
terraform validate
```

Vous voyez l'erreur de syntaxe. Corrigez-la.

3. Formatez tous les fichiers `.tf` automatiquement :

```bash
terraform fmt -recursive
```

4. Creez un script de validation pre-commit :

```bash
#!/bin/bash
# check-terraform.sh
terraform validate
terraform fmt -check -recursive
```

Rendez-le executable :

```bash
chmod +x check-terraform.sh
./check-terraform.sh
```

**Question** : Pourquoi est-il important de valider Terraform **avant** d'executer `terraform apply` ? Quels autres checks pourriez-vous ajouter (ex: linting) ?

---

## Bonus 2 : Data sources et references (20 min)

Utilisez les **data sources** pour charger des donnees existantes dans GCP sans les gerer avec Terraform :

1. Creez manuellement un bucket via la console GCP ou gsutil :

```bash
gsutil mb -l europe-west9 gs://bonus-data-source-bucket/
```

2. Creez un fichier `data_sources.tf` pour referencer ce bucket existant :

```hcl
data "google_storage_bucket" "existing" {
  name = "bonus-data-source-bucket"
}

output "bucket_self_link" {
  value = data.google_storage_bucket.existing.self_link
}
```

3. Planifiez et voyez ce que Terraform recupere :

```bash
terraform plan
```

Remarquez que `data.google_storage_bucket.existing` n'est **pas** dans le state — c'est une reference a une ressource existante.

4. Affichez les attributs du bucket :

```bash
terraform apply
terraform state show 'data.google_storage_bucket.existing'
```

5. Nettoyez :

```bash
gsutil rm -r gs://bonus-data-source-bucket/
```

**Question** : Quand utiliseriez-vous une data source plutot que de gerer une ressource directement ? (Ex: infrastructure pre-existante, separation des responsabilites)

---

## Bonus 3 : Outputs, local-exec et templating (20 min)

Utilisez des **outputs** pour exporter des informations et **local-exec** pour executer des scripts apres la creation :

1. Modifiez `main.tf` pour creer un bucket et l'exporter :

```hcl
resource "google_storage_bucket" "bonus" {
  name     = "bonus-${var.bucket_name}"
  location = var.region
}

output "bucket_name" {
  value       = google_storage_bucket.bonus.name
  description = "Nom du bucket cree"
}

output "bucket_url" {
  value       = "gs://${google_storage_bucket.bonus.name}"
  description = "URL du bucket"
}
```

2. Ajoutez une ressource `local_file` pour creer un fichier local avec les infos du bucket :

```hcl
resource "local_file" "bucket_info" {
  filename = "${path.module}/bucket_info.txt"
  content  = <<EOT
Bucket: ${google_storage_bucket.bonus.name}
URL: gs://${google_storage_bucket.bonus.name}
Created: ${google_storage_bucket.bonus.time_created}
EOT

  depends_on = [google_storage_bucket.bonus]
}
```

3. Ajoutez un `provisioner "local-exec"` pour executer un script apres :

```hcl
resource "null_resource" "post_create" {
  provisioner "local-exec" {
    command = "echo 'Bucket ${google_storage_bucket.bonus.name} cree le $(date)' >> /tmp/bucket_log.txt"
  }

  depends_on = [google_storage_bucket.bonus]
}
```

4. Appliquez et observez :

```bash
terraform apply -var="bucket_name=<VOTRE_NOM>"
terraform output
cat bucket_info.txt
cat /tmp/bucket_log.txt
```

5. Nettoyez :

```bash
terraform destroy -var="bucket_name=<VOTRE_NOM>"
```

**Question** : Pourquoi `local-exec` n'est-il pas idéal pour les vraies productions ? Quand est-ce que c'est acceptable ? Quelle alternative proposeriez-vous ?

---

## Bonus 4 : Modules avec formes complexes (20 min)

Creez un **module reutilisable** qui accepte une liste de buckets et les cree en boucle :

1. Creez une structure de module :

```bash
mkdir -p modules/buckets
touch modules/buckets/{main.tf,variables.tf,outputs.tf}
```

2. Ecrivez `modules/buckets/variables.tf` :

```hcl
variable "buckets" {
  type = list(object({
    name     = string
    location = string
    labels   = optional(map(string), {})
  }))
  description = "Liste de buckets a creer"
}

variable "environment" {
  type    = string
  default = "dev"
}
```

3. Ecrivez `modules/buckets/main.tf` avec une boucle `for_each` :

```hcl
resource "google_storage_bucket" "buckets" {
  for_each = { for b in var.buckets : b.name => b }

  name     = "${var.environment}-${each.value.name}"
  location = each.value.location
  labels = merge(
    each.value.labels,
    {
      managed_by = "terraform"
      environment = var.environment
    }
  )
}
```

4. Ecrivez `modules/buckets/outputs.tf` :

```hcl
output "bucket_names" {
  value = [for b in google_storage_bucket.buckets : b.name]
}

output "bucket_urls" {
  value = { for name, b in google_storage_bucket.buckets : name => "gs://${b.name}" }
}
```

5. Utilisez le module dans `main.tf` :

```hcl
module "my_buckets" {
  source      = "./modules/buckets"
  environment = "training"

  buckets = [
    {
      name     = "logs"
      location = "EU"
      labels = {
        type = "logs"
      }
    },
    {
      name     = "backups"
      location = "EU"
      labels = {
        type = "backups"
      }
    },
    {
      name     = "data"
      location = "US"
    }
  ]
}

output "all_buckets" {
  value = module.my_buckets.bucket_urls
}
```

6. Appliquez :

```bash
terraform init
terraform plan
terraform apply
terraform output all_buckets
```

7. Nettoyez :

```bash
terraform destroy
```

**Question** : Quel est l'avantage d'utiliser `for_each` avec des objets vs une simple liste ? Comment cela change-t-il la lifecycle des ressources si vous en supprimez une ?
