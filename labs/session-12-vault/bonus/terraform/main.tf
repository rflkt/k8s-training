# Bonus 1 : la meme configuration Vault que les etapes 3 a 5, en Terraform.
# Chaque app est une entree de var.apps ; ajouter une app = ajouter 4 lignes.
#
# Usage (Vault du lab, mode dev) :
#   kubectl -n vault port-forward svc/vault 8200:8200 &
#   export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root
#   terraform init && terraform apply

terraform {
  required_version = ">= 1.13"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
}

# Lit VAULT_ADDR et VAULT_TOKEN dans l'environnement. En CI, pas de token
# statique : voir le bonus 2 (login JWT avec le token OIDC de GitHub).
provider "vault" {}

variable "apps" {
  description = "Une entree par application : son namespace et son login base de donnees."
  type = map(object({
    namespace = string
    db_user   = string
  }))
  default = {
    api2 = { namespace = "exercices", db_user = "api2_app" }
  }
}

# Les mounts kv/ et database/ et la methode kubernetes/ existent deja
# (crees a la main aux etapes 3 a 5). On les reference sans les gerer ;
# sur un Vault neuf, on les declarerait ici avec vault_mount et vault_auth_backend.
locals {
  kv_mount       = "kv"
  database_mount = "database"
  k8s_auth       = "kubernetes"
}

resource "vault_policy" "app" {
  for_each = var.apps
  name     = each.key
  policy   = <<-HCL
    path "${local.kv_mount}/data/${each.value.namespace}/${each.key}" {
      capabilities = ["read"]
    }
    path "${local.database_mount}/static-creds/${each.key}" {
      capabilities = ["read"]
    }
  HCL
}

resource "vault_kubernetes_auth_backend_role" "app" {
  for_each                         = var.apps
  backend                          = local.k8s_auth
  role_name                        = each.key
  bound_service_account_names      = [each.key]
  bound_service_account_namespaces = [each.value.namespace]
  audience                         = "vault"
  token_policies                   = [vault_policy.app[each.key].name]
  token_ttl                        = 1200
}

resource "vault_database_secret_backend_static_role" "app" {
  for_each = var.apps
  backend  = local.database_mount
  name     = each.key
  db_name  = "app"
  username = each.value.db_user
  # En production : une rotation planifiee a une heure creuse plutot qu'une
  # periode, pour que la fenetre de rotation tombe quand personne n'ecrit.
  #   rotation_schedule = "0 3 * * *"
  rotation_period = 3600
}
