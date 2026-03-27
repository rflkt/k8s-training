# Session 9 — Terraform Apps & Helm
#
# Deploy applications to Kubernetes using a reusable Terraform module.

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

# ---------- Namespace ----------

resource "kubernetes_namespace" "exercices" {
  metadata {
    name = "exercices"
  }
}

# ---------- API Deployment ----------
# TODO: Call the app module to deploy the API
# Hints:
#   source    = "./modules/app"
#   app_name  = "api"
#   namespace = kubernetes_namespace.exercices.metadata[0].name
#   image     = "europe-west9-docker.pkg.dev/cloud-447406/training/api:v1"
#   port      = 8080
#   env_vars  = { ENVIRONMENT = "training" }

# ---------- Frontend Deployment ----------
# TODO: Call the app module to deploy the frontend
# Hints:
#   source         = "./modules/app"
#   app_name       = "frontend"
#   image          = "europe-west9-docker.pkg.dev/cloud-447406/training/frontend:v1"
#   port           = 80
#   enable_ingress = true
#   host           = "frontend.training.local"

# ---------- CSI SecretProviderClass ----------
# TODO: Add a kubernetes_manifest resource for the SecretProviderClass
# The SecretProviderClass should:
#   - Use provider "gcp"
#   - Mount a secret named "training-api-key" from GCP Secret Manager
