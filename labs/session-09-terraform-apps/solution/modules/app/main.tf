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

# ---------- IngressRoute (optional) ----------

resource "kubernetes_manifest" "ingress_route" {
  count = var.enable_ingress ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"

    metadata = {
      name      = var.app_name
      namespace = var.namespace
    }

    spec = {
      entryPoints = ["web"]

      routes = [
        {
          match = "Host(`${var.host}`)"
          kind  = "Rule"

          services = [
            {
              name = kubernetes_service.app.metadata[0].name
              port = 80
            }
          ]
        }
      ]
    }
  }
}
