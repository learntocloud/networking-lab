# Firewall rules - includes intentional misconfigurations for incidents

# Bastion SSH from internet (expected)
resource "google_compute_firewall" "allow_ssh_bastion" {
  name    = "allow-ssh-bastion-${var.deployment_id}"
  network = google_compute_network.main.name

  direction = "INGRESS"
  priority  = 1000

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["bastion"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Web SSH from anywhere (INC-4524 - should be restricted to bastion subnet)
resource "google_compute_firewall" "allow_ssh_web" {
  name    = "allow-ssh-web-${var.deployment_id}"
  network = google_compute_network.main.name

  direction = "INGRESS"
  priority  = 1000

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "allow_ssh_api" {
  name    = "allow-ssh-api-${var.deployment_id}"
  network = google_compute_network.main.name

  direction = "INGRESS"
  priority  = 1000

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["api"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "allow_ssh_db" {
  name    = "allow-ssh-db-${var.deployment_id}"
  network = google_compute_network.main.name

  direction = "INGRESS"
  priority  = 1000

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["db"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Web HTTP/HTTPS from internet
resource "google_compute_firewall" "allow_http_https" {
  name    = "allow-http-https-web-${var.deployment_id}"
  network = google_compute_network.main.name

  direction = "INGRESS"
  priority  = 1000

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

# ICMP from anywhere (INC-4524 - should be restricted)
resource "google_compute_firewall" "allow_icmp" {
  name    = "allow-icmp-${var.deployment_id}"
  network = google_compute_network.main.name

  direction = "INGRESS"
  priority  = 1000

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web", "api", "db"]

  allow {
    protocol = "icmp"
  }
}

# Database access too broad (INC-4524)
resource "google_compute_firewall" "allow_postgres" {
  name    = "allow-postgres-${var.deployment_id}"
  network = google_compute_network.main.name

  direction = "INGRESS"
  priority  = 1000

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["db"]

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }
}

# API to DB blocked (INC-4523) - higher priority deny
resource "google_compute_firewall" "deny_api_to_db" {
  name    = "deny-api-to-db-${var.deployment_id}"
  network = google_compute_network.main.name

  direction = "INGRESS"
  priority  = 900

  source_tags = ["api"]
  target_tags = ["db"]

  deny {
    protocol = "tcp"
    ports    = ["5432"]
  }
}

# API egress rules (INC-4521)
resource "google_compute_firewall" "allow_api_internal_egress" {
  name    = "allow-api-internal-egress-${var.deployment_id}"
  network = google_compute_network.main.name

  direction = "EGRESS"
  priority  = 900

  destination_ranges = [var.vpc_cidr]
  target_tags        = ["api"]

  allow {
    protocol = "all"
  }
}

resource "google_compute_firewall" "deny_api_internet_egress" {
  name    = "deny-api-internet-egress-${var.deployment_id}"
  network = google_compute_network.main.name

  direction = "EGRESS"
  priority  = 1000

  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["api"]

  deny {
    protocol = "all"
  }
}
