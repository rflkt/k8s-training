output "node_pool_name" {
  description = "Name of the node pool"
  value       = google_container_node_pool.pool.name
}
