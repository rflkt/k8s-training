output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.cluster.cluster_endpoint
}

output "cluster_name" {
  description = "GKE cluster name"
  value       = module.cluster.cluster_name
}

output "kubeconfig_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${module.cluster.cluster_name} --zone ${var.zone} --project ${var.project_id}"
}

output "node_pool_name" {
  description = "Name of the node pool"
  value       = module.node_pool.node_pool_name
}
