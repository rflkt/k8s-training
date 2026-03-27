output "cluster_id" {
  description = "The full resource ID of the GKE cluster"
  value       = google_container_cluster.cluster.id
}

output "cluster_endpoint" {
  description = "The IP address of the GKE cluster control plane"
  value       = google_container_cluster.cluster.endpoint
}

output "cluster_name" {
  description = "The name of the GKE cluster"
  value       = google_container_cluster.cluster.name
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate for the cluster"
  value       = google_container_cluster.cluster.master_auth[0].cluster_ca_certificate
}
