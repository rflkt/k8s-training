resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.location
  project  = var.project_id

  # Remove the default node pool — we manage our own
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network
  subnetwork = var.subnetwork

  # Enable Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Allow access from anywhere (training only — restrict in production!)
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "all"
    }
  }
}
