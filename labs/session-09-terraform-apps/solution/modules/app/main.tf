# Reusable application module (Solution)
#
# Creates a Kubernetes Deployment, Service, and an optional Traefik IngressRoute.

# ---------- Deployment ----------

resource "kubernetes_deployment" "app" {
  metadata {
    name      = var.app_name
    namespace = var.namespace

    labels = {
      app = var.app_name
    }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = var.app_name
      }
    }

    template {
      metadata {
        labels = {
          app = var.app_name
        }
      }

      spec {
        container {
          name  = var.app_name
          image = var.image

          port {
            container_port = var.port
          }

          # Inject environment variables from the env_vars map
          dynamic "env" {
            for_each = var.env_vars
            content {
              name  = env.key
              value = env.value
            }
          }
        }
      }
    }
  }
}

# ---------- Service ----------

resource "kubernetes_service" "app" {
  metadata {
    name      = var.app_name
    namespace = var.namespace
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = var.app_name
    }

    port {
      port        = 80
      target_port = var.port
      protocol    = "TCP"
    }
  }
}

# ---------- Ingress (optional) ----------
#
# Native kubernetes_ingress_v1 (built-in API) routed by Traefik via
# ingress_class_name. We deliberately avoid the Traefik IngressRoute CRD here:
# kubernetes_manifest looks up the CRD at PLAN time, so it would break
# `terraform plan` on any cluster where Traefik isn't installed yet. A native
# Ingress always plans, and Traefik picks it up through its Ingress provider.

resource "kubernetes_ingress_v1" "app" {
  count = var.enable_ingress ? 1 : 0

  metadata {
    name      = var.app_name
    namespace = var.namespace
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = var.host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.app.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
