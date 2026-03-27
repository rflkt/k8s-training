variable "pool_name" {
  description = "Name of the node pool"
  type        = string
}

variable "location" {
  description = "Zone for the node pool"
  type        = string
}

variable "cluster_id" {
  description = "ID of the GKE cluster"
  type        = string
}

variable "machine_type" {
  description = "Machine type for nodes"
  type        = string
  default     = "e2-medium"
}

variable "node_count" {
  description = "Number of nodes"
  type        = number
  default     = 1
}

variable "spot" {
  description = "Use spot VMs (cheaper, can be preempted)"
  type        = bool
  default     = true
}
