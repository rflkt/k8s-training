variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "europe-west9"
}

variable "bucket_name" {
  description = "Name of the GCS bucket (must be globally unique)"
  type        = string
}
