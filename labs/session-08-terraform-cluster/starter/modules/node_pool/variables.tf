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
  description = "Initial number of nodes (autoscaling adjusts within min/max)"
  type        = number
  default     = 1
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
  description = "Use spot VMs (cheaper, can be preempted)"
  type        = bool
  default     = true
}

variable "taint_key" {
  description = "Optional node taint key. Leave empty for no taint."
  type        = string
  default     = ""
}

variable "taint_value" {
  description = "Node taint value (used only when taint_key is set)"
  type        = string
  default     = ""
}

variable "taint_effect" {
  description = "Node taint effect: NO_SCHEDULE, PREFER_NO_SCHEDULE, or NO_EXECUTE"
  type        = string
  default     = "NO_SCHEDULE"
}
