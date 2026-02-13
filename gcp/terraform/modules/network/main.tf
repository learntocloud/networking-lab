# Network Module - Contains intentional misconfigurations for learning
# Students will need to fix these issues

resource "google_compute_network" "main" {
  name                    = "vpc-networking-lab-${var.deployment_id}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "public" {
  name          = "subnet-public-${var.deployment_id}"
  ip_cidr_range = var.public_subnet_cidr
  region        = var.region
  network       = google_compute_network.main.id
}

resource "google_compute_subnetwork" "private" {
  name          = "subnet-private-${var.deployment_id}"
  ip_cidr_range = var.private_subnet_cidr
  region        = var.region
  network       = google_compute_network.main.id

  private_ip_google_access = true
}

resource "google_compute_subnetwork" "database" {
  name          = "subnet-database-${var.deployment_id}"
  ip_cidr_range = var.database_subnet_cidr
  region        = var.region
  network       = google_compute_network.main.id

  private_ip_google_access = true
}

# =============================================================================
# CLOUD NAT (for private subnet outbound internet access)
# =============================================================================

resource "google_compute_router" "main" {
  name    = "router-${var.deployment_id}"
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "main" {
  name                               = "nat-${var.deployment_id}"
  router                             = google_compute_router.main.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private.name
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  subnetwork {
    name                    = google_compute_subnetwork.database.name
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}
