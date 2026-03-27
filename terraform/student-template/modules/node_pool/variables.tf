variable "pool_name" {
  description = "Name of the node pool"
  type        = string
}

variable "location" {
  description = "GCP zone or region for the node pool"
  type        = string
}

variable "cluster_id" {
  description = "The ID of the GKE cluster this node pool belongs to"
  type        = string
}

variable "machine_type" {
  description = "GCE machine type for the nodes"
  type        = string
  default     = "e2-small"
}

variable "node_count" {
  description = "Initial number of nodes in the pool"
  type        = number
  default     = 2
}

variable "min_node_count" {
  description = "Minimum number of nodes for autoscaling"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes for autoscaling"
  type        = number
  default     = 3
}

variable "spot" {
  description = "Use spot (preemptible) VMs to reduce costs"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment label applied to nodes"
  type        = string
  default     = "training"
}
