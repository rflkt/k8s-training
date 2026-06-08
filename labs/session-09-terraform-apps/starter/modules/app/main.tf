# Reusable application module
#
# This module creates a Kubernetes Deployment, Service, and an optional
# Traefik IngressRoute for a single application.

# ---------- Deployment ----------
# TODO: Create a kubernetes_deployment resource
# Requirements:
#   - metadata: name = var.app_name, namespace = var.namespace, labels = { app = var.app_name }
#   - spec.replicas = var.replicas
#   - spec.selector.match_labels = { app = var.app_name }
#   - template labels = { app = var.app_name }
#   - container: name = var.app_name, image = var.image, port = var.port
#   - Use a dynamic block for env vars from var.env_vars map

# ---------- Service ----------
# TODO: Create a kubernetes_service resource
# Requirements:
#   - metadata: name = var.app_name, namespace = var.namespace
#   - spec.type = "ClusterIP"
#   - spec.selector = { app = var.app_name }
#   - spec.port: port = 80, target_port = var.port

# ---------- Ingress (optional) ----------
# TODO: Create a native kubernetes_ingress_v1 (NOT the Traefik IngressRoute CRD —
#       a kubernetes_manifest CRD would break `terraform plan` before Traefik exists).
# Only create this resource if var.enable_ingress is true (use count)
# Requirements:
#   - metadata: name = var.app_name, namespace = var.namespace
#   - spec.ingress_class_name = "traefik"
#   - spec.rule.host = var.host
#   - rule.http.path: path = "/", path_type = "Prefix"
#   - backend.service: name = var.app_name, port.number = 80
