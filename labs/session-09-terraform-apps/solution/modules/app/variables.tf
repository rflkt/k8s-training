# Variables for the app module

variable "app_name" {
  description = "Name of the application (used for resource names and labels)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to deploy into"
  type        = string
}

variable "image" {
  description = "Container image to deploy (e.g. registry/image:tag)"
  type        = string
}

variable "replicas" {
  description = "Number of pod replicas"
  type        = number
  default     = 1
}

variable "port" {
  description = "Container port the application listens on"
  type        = number
  default     = 8080
}

variable "env_vars" {
  description = "Map of environment variables to inject into the container"
  type        = map(string)
  default     = {}
}

variable "enable_ingress" {
  description = "Whether to create a Traefik IngressRoute for external access"
  type        = bool
  default     = false
}

variable "host" {
  description = "Hostname for the Traefik IngressRoute (required if enable_ingress is true)"
  type        = string
  default     = ""
}
