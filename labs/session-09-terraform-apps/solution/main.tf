# Session 9 — Terraform Apps & Helm (Solution)
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

module "api" {
  source    = "./modules/app"
  app_name  = "api"
  namespace = kubernetes_namespace.exercices.metadata[0].name
  image     = "europe-west9-docker.pkg.dev/cloud-447406/training/api:v1"
  replicas  = 2
  port      = 8080

  env_vars = {
    ENVIRONMENT = "training"
  }
}

# ---------- Frontend Deployment ----------

module "frontend" {
  source         = "./modules/app"
  app_name       = "frontend"
  namespace      = kubernetes_namespace.exercices.metadata[0].name
  image          = "europe-west9-docker.pkg.dev/cloud-447406/training/frontend:v1"
  replicas       = 1
  port           = 80
  enable_ingress = true
  host           = "frontend.training.local"

  env_vars = {
    API_URL = "http://api.exercices.svc.cluster.local:80"
  }
}

# ---------- CSI SecretProviderClass ----------

resource "kubernetes_manifest" "api_secret_provider" {
  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"

    metadata = {
      name      = "api-secrets"
      namespace = kubernetes_namespace.exercices.metadata[0].name
    }

    spec = {
      provider = "gcp"

      parameters = {
        secrets = yamlencode([
          {
            resourceName = "projects/cloud-447406/secrets/training-api-key/versions/latest"
            path         = "api-key"
          }
        ])
      }
    }
  }
}
