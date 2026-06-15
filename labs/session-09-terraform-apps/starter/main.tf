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
  config_path = var.kubeconfig
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig
  }
}

# ---------- Variables ----------

variable "kubeconfig" {
  description = "Path to the kubeconfig used by the providers. On the shared cluster, point at the trainee kubeconfig from `make training-export-kubeconfig`."
  type        = string
  default     = "~/.kube/config"
}

variable "namespace" {
  description = "Namespace to deploy the apps into (e.g. trainee-01 on the shared cluster)"
  type        = string
  default     = "exercices"
}

variable "create_namespace" {
  description = "Create the namespace (false on a shared cluster where it already exists)"
  type        = bool
  default     = true
}

variable "install_traefik" {
  description = "Install Traefik via Helm. Leave false on the shared cluster (trainer installs it); true only on your own cluster."
  type        = bool
  default     = false
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
# On the SHARED cluster the trainer already installed Traefik and you only have
# namespaced `edit` rights, so gate this with `count = var.install_traefik ? 1 : 0`
# and leave install_traefik = false. Add it only on your own (admin) cluster.
# Hints:
#   count            = var.install_traefik ? 1 : 0
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
#   host           = "frontend.${var.namespace}.training.local"  # unique per trainee
#   depends_on     = [kubernetes_namespace.exercices, helm_release.traefik]

# ---------- CSI SecretProviderClass (optional) ----------
# TODO (optional, advanced): Add a kubernetes_manifest for a SecretProviderClass,
# guarded by `count = var.enable_secret_csi ? 1 : 0`.
# NOTE: kubernetes_manifest resolves the CRD at PLAN time, so this only works
# once the secrets-store CSI driver is installed on the cluster (see README).
#   - Use provider "gcp"
#   - Mount the secret "training-api-key" from GCP Secret Manager
