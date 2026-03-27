variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "location" {
  description = "The zone for the cluster (e.g. europe-west9-a)"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "network" {
  description = "VPC network name"
  type        = string
}

variable "subnetwork" {
  description = "Subnet name"
  type        = string
}
