variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "location" {
  description = "GCP zone or region for the cluster (e.g. europe-west9-b)"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "network" {
  description = "Name of the VPC network"
  type        = string
}

variable "subnetwork" {
  description = "Name of the subnet"
  type        = string
}
