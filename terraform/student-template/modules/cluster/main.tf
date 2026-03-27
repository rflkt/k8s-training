# =============================================================================
# Cluster Module — GKE Control Plane
# =============================================================================
# Creates a GKE cluster with the default node pool removed.
# We manage node pools separately so we have full control over their config.
# =============================================================================

resource "google_container_cluster" "cluster" {
  name     = var.cluster_name
  location = var.location
  project  = var.project_id

  # We remove the default node pool immediately after creation.
  # Our own node pool is managed by the node_pool module.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Use VPC-native networking (alias IPs). This is required for most GKE features.
  # Empty ip_allocation_policy block = let GCP auto-assign Pod and Service CIDRs.
  network    = var.network
  subnetwork = var.subnetwork

  ip_allocation_policy {
    # GKE will automatically allocate secondary ranges for Pods and Services
  }

  # Workload Identity lets pods authenticate as GCP service accounts
  # without needing JSON key files.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # For training purposes, allow access from any IP.
  # In production you would restrict this to your office/VPN IP ranges.
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks (training only)"
    }
  }

  # Suppress the default node pool deletion warning
  deletion_protection = false
}
