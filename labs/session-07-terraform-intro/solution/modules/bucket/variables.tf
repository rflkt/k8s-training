variable "bucket_name" {
  description = "Name of the GCS bucket (must be globally unique)"
  type        = string
}

variable "location" {
  description = "GCS bucket location"
  type        = string
}

variable "force_destroy" {
  description = "Allow bucket deletion even if it contains objects"
  type        = bool
  default     = false
}

variable "versioning_enabled" {
  description = "Enable object versioning"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to the bucket"
  type        = map(string)
  default     = {}
}

variable "lifecycle_age_days" {
  description = "Number of days after which objects are deleted (null to disable)"
  type        = number
  default     = null
}
