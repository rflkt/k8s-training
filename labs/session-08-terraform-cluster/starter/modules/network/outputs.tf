output "network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = google_compute_subnetwork.subnet.name
}

output "network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.vpc.id
}
