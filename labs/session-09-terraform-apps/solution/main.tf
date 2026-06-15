# Session 9 — Terraform Apps & Helm (Solution)
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
  description = "Path to the kubeconfig used by the kubernetes/helm providers. On the shared cluster, point this at the trainee kubeconfig from `make training-export-kubeconfig` (e.g. ./training-kubeconfig.yaml)."
  type        = string
  default     = "~/.kube/config"
}

variable "namespace" {
  description = "Namespace to deploy the apps into. On the shared cluster, use your assigned namespace (e.g. trainee-01)."
  type        = string
  default     = "exercices"
}

variable "install_traefik" {
  description = "Install Traefik via Helm. Leave false on the shared cluster — the trainer installs Traefik once (you only have namespaced `edit` rights). Set true only on your own cluster where you are cluster-admin."
  type        = bool
  default     = false
}

variable "create_namespace" {
  description = "Create the namespace. true for a self-contained cluster; set false on a shared cluster where the namespace is pre-created and you only have namespaced access."
  type        = bool
  default     = true
}

variable "enable_secret_csi" {
  description = "Create the SecretProviderClass. Requires the secrets-store CSI driver installed on the cluster (see README) — leave false otherwise, or `terraform plan` fails looking up the CRD."
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
# This is the "Helm" half of the session: Terraform drives a Helm release.
# Gated by install_traefik: on the shared training cluster the trainer installs
# Traefik once (you only have namespaced `edit`), so leave this false there.

resource "helm_release" "traefik" {
  count = var.install_traefik ? 1 : 0

  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = "27.0.0"
  namespace        = "traefik"
  create_namespace = true
}

# ---------- API Deployment ----------

module "api" {
  source    = "./modules/app"
  app_name  = "api"
  namespace = var.namespace
  image     = "europe-west9-docker.pkg.dev/cloud-447406/training/api:v1"
  replicas  = 2
  port      = 8080

  env_vars = {
    ENVIRONMENT = "training"
  }

  depends_on = [kubernetes_namespace.exercices]
}

# ---------- Frontend Deployment ----------

module "frontend" {
  source         = "./modules/app"
  app_name       = "frontend"
  namespace      = var.namespace
  image          = "europe-west9-docker.pkg.dev/cloud-447406/training/frontend:v1"
  replicas       = 1
  port           = 80
  enable_ingress = true
  # Host includes the namespace so concurrent trainees on the shared cluster
  # don't collide on the same Ingress host (e.g. frontend.trainee-01.training.local).
  host = "frontend.${var.namespace}.training.local"

  env_vars = {
    API_URL = "http://api.${var.namespace}.svc.cluster.local:80"
  }

  depends_on = [kubernetes_namespace.exercices, helm_release.traefik]
}

# ---------- CSI SecretProviderClass (optional) ----------
# Mounts a GCP Secret Manager secret into pods via the secrets-store CSI driver.
# Gated by enable_secret_csi: kubernetes_manifest resolves the CRD at PLAN time,
# so this only works once the secrets-store CSI driver is installed (see README).

resource "kubernetes_manifest" "api_secret_provider" {
  count = var.enable_secret_csi ? 1 : 0

  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"

    metadata = {
      name      = "api-secrets"
      namespace = var.namespace
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
