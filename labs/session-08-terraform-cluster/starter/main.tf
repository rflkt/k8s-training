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

# TODO: Create the network module
# module "network" {
#   source = "./modules/network"
#
#   network_name = "${var.student_name}-vpc"
#   subnet_name  = "${var.student_name}-subnet"
#   subnet_cidr  = "10.10.0.0/24"
#   region       = var.region
# }

# TODO: Create the cluster module
# module "cluster" {
#   source = "./modules/cluster"
#
#   cluster_name = "${var.student_name}-cluster"
#   location     = var.zone
#   project_id   = var.project_id
#   network      = module.network.network_name
#   subnetwork   = module.network.subnet_name
# }

# TODO: Create the node pool module
# module "node_pool" {
#   source = "./modules/node_pool"
#
#   pool_name    = "${var.student_name}-pool"
#   location     = var.zone
#   cluster_id   = module.cluster.cluster_id
#   machine_type = "e2-medium"
#   node_count   = 1
#   spot         = true
# }
