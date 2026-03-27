# =============================================================================
# Outputs
# =============================================================================

output "cluster_name" {
  description = "The name of the GKE cluster"
  value       = module.cluster.cluster_name
}

output "cluster_endpoint" {
  description = "The IP address of the GKE cluster control plane"
  value       = module.cluster.cluster_endpoint
  sensitive   = true
}

output "kubeconfig_command" {
  description = "Run this command to configure kubectl access to your cluster"
  value       = "gcloud container clusters get-credentials ${module.cluster.cluster_name} --zone ${var.zone} --project ${var.project_id}"
}

output "project_id" {
  description = "The GCP project ID"
  value       = var.project_id
}
