# =============================================================================
# Input Variables
# =============================================================================

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The GCP region for regional resources (VPC, subnet, NAT)"
  type        = string
  default     = "europe-west9"
}

variable "zone" {
  description = "The GCP zone for zonal resources (GKE cluster, node pool)"
  type        = string
  default     = "europe-west9-b"
}

variable "student_name" {
  description = "Your first name (lowercase, no spaces). Used to prefix all resource names so each student's resources are unique."
  type        = string
}
