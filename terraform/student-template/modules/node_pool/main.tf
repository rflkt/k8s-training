# =============================================================================
# Node Pool Module — GKE Worker Nodes
# =============================================================================
# Creates a managed node pool with autoscaling.
# Uses spot VMs by default to minimize training costs.
# =============================================================================

resource "google_container_node_pool" "pool" {
  name     = var.pool_name
  location = var.location
  cluster  = var.cluster_id

  # Initial number of nodes per zone
  node_count = var.node_count

  # Autoscaling — GKE will add/remove nodes based on resource demand
  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  # Node management — let GKE handle repairs and upgrades automatically
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.machine_type

    # Spot VMs cost ~60-90% less than regular VMs.
    # They can be preempted at any time, but that's fine for training.
    spot = var.spot

    # OAuth scopes control what GCP APIs the node can access.
    # These are the minimum scopes needed for a functional GKE node.
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only",
    ]

    labels = {
      environment = var.environment
    }

    metadata = {
      # Prevent pods from using the node's metadata server directly
      disable-legacy-endpoints = "true"
    }
  }
}
