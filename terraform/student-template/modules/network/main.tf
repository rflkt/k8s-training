# =============================================================================
# Network Module — VPC, Subnet, Cloud NAT
# =============================================================================
# Creates the networking foundation for the GKE cluster:
#   - A custom VPC with no auto-created subnets
#   - A single subnet for the cluster nodes
#   - A Cloud Router + Cloud NAT so nodes can pull images and reach the internet
# =============================================================================

# Custom VPC — we disable auto subnets so we control the IP ranges ourselves.
resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

# Subnet for the GKE nodes. A /20 gives us 4094 usable IPs — more than enough.
resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
}

# Cloud Router — required by Cloud NAT to advertise routes.
resource "google_compute_router" "router" {
  name    = "${var.network_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# Cloud NAT — allows nodes without external IPs to reach the internet.
# AUTO_ONLY means GCP automatically allocates the NAT IP addresses.
resource "google_compute_router_nat" "nat" {
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
