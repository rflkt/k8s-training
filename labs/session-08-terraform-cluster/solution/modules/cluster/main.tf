resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.location
  project  = var.project_id

  # Remove the default node pool — we manage our own
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network
  subnetwork = var.subnetwork

  # VPC-native networking (alias IPs) — required for modern GKE features.
  # Empty block = GKE auto-allocates the Pod and Service ranges.
  ip_allocation_policy {}

  # Allow `terraform destroy` to delete this cluster.
  # Defaults to true (protected), which makes the mandatory cleanup step fail.
  deletion_protection = false

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
