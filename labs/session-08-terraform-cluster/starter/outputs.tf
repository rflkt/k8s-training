# TODO: Add output for the cluster endpoint
# output "cluster_endpoint" {
#   description = "GKE cluster endpoint"
#   value       = module.cluster.cluster_endpoint
# }

# TODO: Add output for the kubeconfig command
# output "kubeconfig_command" {
#   description = "Command to configure kubectl"
#   value       = "gcloud container clusters get-credentials ${module.cluster.cluster_name} --zone ${var.zone} --project ${var.project_id}"
# }
