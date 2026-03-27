# Outputs for the app module

output "service_name" {
  description = "Name of the Kubernetes Service created for this application"
  value       = kubernetes_service.app.metadata[0].name
}

output "service_url" {
  description = "Internal cluster URL for this application"
  value       = "http://${kubernetes_service.app.metadata[0].name}.${var.namespace}.svc.cluster.local:80"
}
