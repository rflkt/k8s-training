variable "network_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet (e.g. 10.0.0.0/20)"
  type        = string
}

variable "region" {
  description = "GCP region for the subnet and NAT"
  type        = string
}
