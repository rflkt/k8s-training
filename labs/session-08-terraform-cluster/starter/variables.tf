variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west9"
}

variable "zone" {
  description = "GCP zone for the zonal cluster"
  type        = string
  default     = "europe-west9-a"
}

variable "student_name" {
  description = "Student name used as prefix for all resources"
  type        = string
}
