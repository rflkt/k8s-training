# Session 9 — Terraform Apps & Helm
#
# Deploy applications to Kubernetes using a reusable Terraform module,
# and install the Traefik ingress controller via the Helm provider.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# ---------- Variables ----------

variable "namespace" {
  description = "Namespace to deploy the apps into"
  type        = string
  default     = "exercices"
}

variable "create_namespace" {
  description = "Create the namespace (false on a shared cluster where it already exists)"
  type        = bool
  default     = true
}

variable "enable_secret_csi" {
  description = "Create the SecretProviderClass (requires the secrets-store CSI driver — see README)"
  type        = bool
  default     = false
}

# ---------- Namespace ----------

resource "kubernetes_namespace" "exercices" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

# ---------- Traefik ingress controller (via Helm) ----------
# TODO: Add a helm_release resource to install Traefik.
# Hints:
#   name             = "traefik"
#   repository       = "https://traefik.github.io/charts"
#   chart            = "traefik"
#   version          = "27.0.0"
#   namespace        = "traefik"
#   create_namespace = true

# ---------- API Deployment ----------
# TODO: Call the app module to deploy the API
# Hints:
#   source     = "./modules/app"
#   app_name   = "api"
#   namespace  = var.namespace
#   image      = "europe-west9-docker.pkg.dev/cloud-447406/training/api:v1"
#   port       = 8080
#   env_vars   = { ENVIRONMENT = "training" }
#   depends_on = [kubernetes_namespace.exercices]

# ---------- Frontend Deployment ----------
# TODO: Call the app module to deploy the frontend (with ingress enabled)
# Hints:
#   source         = "./modules/app"
#   app_name       = "frontend"
#   namespace      = var.namespace
#   image          = "europe-west9-docker.pkg.dev/cloud-447406/training/frontend:v1"
#   port           = 80
#   enable_ingress = true
#   host           = "frontend.training.local"
#   depends_on     = [kubernetes_namespace.exercices, helm_release.traefik]

# ---------- CSI SecretProviderClass (optional) ----------
# TODO (optional, advanced): Add a kubernetes_manifest for a SecretProviderClass,
# guarded by `count = var.enable_secret_csi ? 1 : 0`.
# NOTE: kubernetes_manifest resolves the CRD at PLAN time, so this only works
# once the secrets-store CSI driver is installed on the cluster (see README).
#   - Use provider "gcp"
#   - Mount the secret "training-api-key" from GCP Secret Manager
