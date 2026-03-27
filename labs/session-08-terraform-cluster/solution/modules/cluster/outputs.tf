output "cluster_id" {
  description = "ID of the GKE cluster"
  value       = google_container_cluster.primary.id
}

output "cluster_endpoint" {
  description = "Endpoint of the GKE cluster"
  value       = google_container_cluster.primary.endpoint
}

output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = google_container_cluster.primary.name
}
