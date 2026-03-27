terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Network: VPC + subnet + NAT
module "network" {
  source = "./modules/network"

  network_name = "${var.student_name}-vpc"
  subnet_name  = "${var.student_name}-subnet"
  subnet_cidr  = "10.10.0.0/24"
  region       = var.region
}

# GKE cluster (control plane only, no default node pool)
module "cluster" {
  source = "./modules/cluster"

  cluster_name = "${var.student_name}-cluster"
  location     = var.zone
  project_id   = var.project_id
  network      = module.network.network_name
  subnetwork   = module.network.subnet_name
}

# Node pool with spot VMs for cost savings
module "node_pool" {
  source = "./modules/node_pool"

  pool_name    = "${var.student_name}-pool"
  location     = var.zone
  cluster_id   = module.cluster.cluster_id
  machine_type = "e2-medium"
  node_count   = 1
  spot         = true
}
