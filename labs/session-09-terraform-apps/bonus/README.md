# Session 9 — Exercices Bonus

> Pour ceux qui ont termine le TP principal en avance. Chaque exercice est independant.

---

## Bonus 1 : Blocs dynamiques pour volumes optionnels (20 min)

Utilisez les **blocs dynamiques** pour creer des volumes conditionnels dans votre module applicatif :

1. Modifiez le module `modules/app/variables.tf` pour ajouter une variable optionnelle :

```hcl
variable "enable_cache_volume" {
  type        = bool
  default     = false
  description = "Monter un volume emptyDir pour le cache"
}

variable "cache_mount_path" {
  type        = string
  default     = "/tmp/cache"
  description = "Chemin de montage du cache"
}
```

2. Dans `modules/app/main.tf`, modifiez le Deployment pour utiliser un bloc dynamique :

```hcl
spec {
  template {
    spec {
      container {
        # ... configuration existante ...

        dynamic "volume_mount" {
          for_each = var.enable_cache_volume ? [1] : []
          content {
            name       = "cache"
            mount_path = var.cache_mount_path
          }
        }
      }

      dynamic "volume" {
        for_each = var.enable_cache_volume ? [1] : []
        content {
          name = "cache"
          empty_dir {}
        }
      }
    }
  }
}
```

3. Dans votre `main.tf`, deployer l'API avec le cache :

```hcl
module "api" {
  source              = "./modules/app"
  app_name            = "api"
  namespace           = "exercices"
  image               = "europe-west9-docker.pkg.dev/cloud-447406/training/api:v1"
  enable_cache_volume = true
  cache_mount_path    = "/tmp/cache"
}
```

4. Appliquez et verifiez :

```bash
terraform apply
kubectl get deployment -n exercices api -o yaml | grep -A 10 "volumeMounts\|volumes"
```

5. Verifiez que le cache est accessible :

```bash
kubectl exec -n exercices deploy/api -- ls -la /tmp/cache
```

6. Testez sans le cache (modifiez `enable_cache_volume = false`) et observez le changement de plan :

```bash
terraform plan
# Vous verrez que le volume_mount et volume seront supprimes
```

**Question** : Pourquoi les blocs dynamiques sont-ils utiles pour les configurations optionnelles ? Comment cela simplifie-t-il la maintenance ?

---

## Bonus 2 : for_each pour deploiements multi-applications (20 min)

Utilisez **for_each** pour deployer plusieurs applications avec un seul appel de module :

1. Creez un fichier `apps.tfvars` contenant la configuration de plusieurs apps :

```hcl
applications = {
  api = {
    image  = "europe-west9-docker.pkg.dev/cloud-447406/training/api:v1"
    port   = 8080
    enable_ingress = true
    host   = "api.<NOM>.training.local"
  }
  frontend = {
    image  = "europe-west9-docker.pkg.dev/cloud-447406/training/frontend:v1"
    port   = 80
    enable_ingress = true
    host   = "frontend.<NOM>.training.local"
  }
  redis = {
    image  = "redis:7-alpine"
    port   = 6379
    enable_ingress = false
  }
}
```

2. Dans `main.tf`, definissez une variable pour accepter ce mapping :

```hcl
variable "applications" {
  type = map(object({
    image  = string
    port   = number
    enable_ingress = optional(bool, false)
    host   = optional(string, "")
  }))
  description = "Applications a deployer"
}
```

3. Utilisez `for_each` pour creer un module par app :

```hcl
module "app" {
  for_each = var.applications

  source         = "./modules/app"
  app_name       = each.key
  namespace      = "exercices"
  image          = each.value.image
  port           = each.value.port
  enable_ingress = each.value.enable_ingress
  host           = each.value.host
}
```

4. Creez un output aggrege :

```hcl
output "deployed_apps" {
  value = {
    for name, app in module.app :
    name => {
      service_name = "${name}.exercices.svc.cluster.local"
    }
  }
}
```

5. Appliquez :

```bash
terraform apply -var-file=apps.tfvars
```

6. Verifiez les deployments :

```bash
kubectl get deployments -n exercices
terraform output deployed_apps
```

7. Testez l'ajout d'une nouvelle app (ex: ajoutez `memcached`) dans `apps.tfvars` :

```hcl
memcached = {
  image = "memcached:1-alpine"
  port  = 11211
}
```

Relancez :

```bash
terraform plan -var-file=apps.tfvars
# Vous verrez que seul memcached sera cree
terraform apply -var-file=apps.tfvars
```

**Question** : Quels sont les avantages de `for_each` vs `count` pour les multi-applications ? Comment cela simplifie-t-il les modifications futures ?

---

## Bonus 3 : Exploration des workspaces Terraform (15 min)

Utilisez les **workspaces** pour gerer plusieurs environnements (dev, staging, prod) avec le meme code :

1. Listez les workspaces existants (par defaut, il y a `default`) :

```bash
terraform workspace list
```

2. Creez de nouveaux workspaces :

```bash
terraform workspace new dev
terraform workspace new staging
terraform workspace new prod
```

3. Verifiez que vous etes sur `prod` :

```bash
terraform workspace show
```

4. Modifiez votre `main.tf` pour utiliser le workspace dans les noms :

```hcl
locals {
  env = terraform.workspace
}

module "api" {
  source    = "./modules/app"
  app_name  = "${local.env}-api"  # dev-api, staging-api, prod-api
  namespace = "exercices-${local.env}"
}
```

5. Basculez entre les workspaces et planifiez :

```bash
# Dev
terraform workspace select dev
terraform plan -var-file=apps.tfvars
# Verifiez que les ressources sont nommees avec le prefixe "dev-"

# Staging
terraform workspace select staging
terraform plan -var-file=apps.tfvars
# Verifiez que les ressources sont nommees avec le prefixe "staging-"

# Prod
terraform workspace select prod
terraform plan -var-file=apps.tfvars
# Verifiez que les ressources sont nommees avec le prefixe "prod-"
```

6. Explorez le state par workspace :

```bash
# Le state est stocke dans terraform.tfstate.d/<workspace>/
ls -la terraform.tfstate.d/
terraform state list
```

7. Revenez au workspace par defaut :

```bash
terraform workspace select default
```

8. Nettoyez les workspaces (optionnel) :

```bash
terraform workspace select default
terraform workspace delete dev
terraform workspace delete staging
terraform workspace delete prod
terraform workspace list
```

**Question** : Quels sont les avantages et inconvenients des workspaces par rapport a des repertoires separes ? Quand utiliseriez-vous l'un ou l'autre ?

---

## Bonus 4 : Secrets et variables sensibles (15 min)

Gerez les **secrets** de facon secure en Terraform sans les exposer en plaintext :

1. Modifiez votre `variables.tf` pour ajouter des variables sensibles :

```hcl
variable "database_password" {
  type        = string
  sensitive   = true
  description = "Password de la base de donnees"
}

variable "api_key" {
  type        = string
  sensitive   = true
  description = "Cle API externe"
}
```

2. Creez un fichier `.tfvars` pour les secrets (ATTENTION : ne commiter JAMAIS ce fichier) :

```hcl
# secrets.tfvars (ajouter a .gitignore)
database_password = "super-secret-password-123"
api_key           = "sk-1234567890abcdef"
```

3. Dans votre `main.tf`, utilisez ces secrets dans un ConfigMap K8s :

```hcl
resource "kubernetes_config_map" "secrets_env" {
  metadata {
    name      = "api-secrets-env"
    namespace = "exercices"
  }

  data = {
    DATABASE_PASSWORD = var.database_password
    API_KEY           = var.api_key
  }
}
```

4. Injectez le ConfigMap dans le Deployment. Le module n'a pas (encore) de
   variable pour ca : etendez-le avec une variable optionnelle, puis un bloc
   `env_from` conditionnel dans le `container` (sur le modele du `dynamic "env"`) :

```hcl
# modules/app/variables.tf
variable "env_from_config_map" {
  type    = string
  default = ""
}

# modules/app/main.tf — dans le bloc container
dynamic "env_from" {
  for_each = var.env_from_config_map != "" ? [1] : []
  content {
    config_map_ref {
      name = var.env_from_config_map
    }
  }
}
```

Puis passez `env_from_config_map = "api-secrets-env"` a l'appel du module.

5. Appliquez avec le fichier secrets :

```bash
terraform apply -var-file=secrets.tfvars
```

6. Verifiez que les secrets ne sont **pas** affiches en sortie :

```bash
terraform output  # Les champs marques "sensitive" ne montrent pas leur valeur
```

7. Verifiez dans Kubernetes (attention : ils sont encore lisibles dans etcd !) :

```bash
kubectl get configmap -n exercices api-secrets-env -o yaml
```

8. (Optionnel) Utilisez une vraie gestion de secrets via GCP Secret Manager :

```hcl
resource "google_secret_manager_secret" "database_password" {
  secret_id = "database-password"
}

resource "google_secret_manager_secret_version" "database_password" {
  secret      = google_secret_manager_secret.database_password.id
  secret_data = var.database_password
}

# Montez via le CSI driver (voir modules/secret_manager_csi)
```

**Question** : Pourquoi ne faut-il jamais commiter les fichiers `.tfvars` avec des secrets ? Quelles autres solutions utiliseriez-vous en production (Vault, AWS Secrets Manager, etc.) ?
