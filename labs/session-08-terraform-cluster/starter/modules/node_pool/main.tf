resource "google_container_node_pool" "pool" {
  name     = var.pool_name
  location = var.location
  cluster  = var.cluster_id

  node_config {
    machine_type = var.machine_type
    disk_size_gb = 30
    spot         = var.spot
    disk_type    = "pd-standard"
    image_type   = "COS_CONTAINERD"

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only",
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  initial_node_count = var.node_count

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
