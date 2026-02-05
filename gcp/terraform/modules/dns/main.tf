# DNS Module

resource "google_dns_managed_zone" "internal" {
  name        = "internal-local-${var.deployment_id}"
  dns_name    = "internal.local."
  description = "Private DNS zone for networking lab"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = var.vpc_self_link
    }
  }

  labels = {
    project = "networking-lab"
  }
}
