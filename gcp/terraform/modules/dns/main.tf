# DNS Module

resource "google_dns_managed_zone" "internal" {
  name          = "internal-test-${var.deployment_id}"
  dns_name      = "internal.test."
  description   = "Private DNS zone for networking lab"
  visibility    = "private"
  force_destroy = true

  private_visibility_config {
    networks {
      network_url = var.vpc_self_link
    }
  }

  labels = {
    project = "networking-lab"
  }
}
