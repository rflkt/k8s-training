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

# ---------- IngressRoute (optional) ----------
# TODO: Create a kubernetes_manifest for a Traefik IngressRoute
# Only create this resource if var.enable_ingress is true (use count)
# Requirements:
#   - apiVersion: traefik.io/v1alpha1
#   - kind: IngressRoute
#   - spec.entryPoints = ["web"]
#   - spec.routes: match = "Host(`${var.host}`)", kind = "Rule"
#   - spec.routes.services: name = var.app_name, port = 80
