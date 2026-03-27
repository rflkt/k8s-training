# =============================================================================
# Session 8 — Create Your Own GKE Cluster
# =============================================================================
# This Terraform configuration provisions a minimal GKE cluster on GCP.
# Each student gets their own isolated cluster, prefixed with their name.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

# Google Cloud provider — all resources will be created in this project/region.
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# We need the google_client_config data source to obtain an access token
# that the Kubernetes provider can use to authenticate against our GKE cluster.
data "google_client_config" "default" {}

# Kubernetes provider — configured to talk to the GKE cluster we create below.
# This lets us create Kubernetes resources (namespaces, etc.) from Terraform.
provider "kubernetes" {
  host                   = "https://${module.cluster.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
}

# -----------------------------------------------------------------------------
# Networking — VPC, subnet, Cloud NAT
# -----------------------------------------------------------------------------
# Every GKE cluster needs a VPC network. This module creates:
#   - A custom VPC (no auto-created subnets)
#   - A single subnet with a /20 CIDR block
#   - A Cloud Router + Cloud NAT so nodes can reach the internet

module "network" {
  source = "./modules/network"

  network_name = "${var.student_name}-vpc"
  subnet_name  = "${var.student_name}-subnet"
  subnet_cidr  = "10.0.0.0/20"
  region       = var.region
}

# -----------------------------------------------------------------------------
# GKE Cluster — control plane only (no default node pool)
# -----------------------------------------------------------------------------
# This creates the GKE control plane. We immediately remove the default node
# pool and manage our own node pool separately (see below).

module "cluster" {
  source = "./modules/cluster"

  cluster_name = "${var.student_name}-cluster"
  location     = var.zone
  project_id   = var.project_id
  network      = module.network.network_name
  subnetwork   = module.network.subnet_name
}

# -----------------------------------------------------------------------------
# Node Pool — the worker nodes that run your pods
# -----------------------------------------------------------------------------
# We use spot (preemptible) VMs to save costs during training.
# e2-small instances are sufficient for the exercises.

module "node_pool" {
  source = "./modules/node_pool"

  pool_name      = "${var.student_name}-pool"
  location       = var.zone
  cluster_id     = module.cluster.cluster_id
  machine_type   = "e2-small"
  node_count     = 2
  min_node_count = 1
  max_node_count = 3
  spot           = true
  environment    = "training"
}

# -----------------------------------------------------------------------------
# Kubernetes Namespace — where you will deploy your exercises
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "exercises" {
  metadata {
    name = "exercises"

    labels = {
      managed-by = "terraform"
      student    = var.student_name
    }
  }

  depends_on = [module.node_pool]
}
