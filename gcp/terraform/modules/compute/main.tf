# Compute Module - VMs for the networking lab

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

locals {
  ssh_metadata = "${var.admin_username}:${tls_private_key.ssh.public_key_openssh}"
  ubuntu_image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
}

# =============================================================================
# BASTION HOST (Public Subnet)
# =============================================================================

resource "google_compute_instance" "bastion" {
  name         = "vm-bastion-${var.deployment_id}"
  machine_type = "e2-micro"
  zone         = var.zone

  tags = ["bastion"]

  boot_disk {
    initialize_params {
      image = local.ubuntu_image
    }
  }

  network_interface {
    subnetwork = var.public_subnet_link

    access_config {}
  }

  metadata = {
    "ssh-keys"      = local.ssh_metadata
    "startup-script" = templatefile("${path.module}/templates/bastion-init.sh", {
      ssh_private_key = tls_private_key.ssh.private_key_pem
      admin_username  = var.admin_username
    })
  }

  labels = {
    project = "networking-lab"
    role    = "bastion"
  }
}

# =============================================================================
# WEB SERVER (Private Subnet + Public IP for HTTP/HTTPS testing)
# =============================================================================

resource "google_compute_instance" "web" {
  name         = "vm-web-${var.deployment_id}"
  machine_type = "e2-micro"
  zone         = var.zone

  tags = ["web"]

  boot_disk {
    initialize_params {
      image = local.ubuntu_image
    }
  }

  network_interface {
    subnetwork = var.private_subnet_link

    access_config {}
  }

  metadata = {
    "ssh-keys"      = local.ssh_metadata
    "startup-script" = templatefile("${path.module}/templates/web-init.sh", {
      admin_username = var.admin_username
    })
  }

  labels = {
    project = "networking-lab"
    role    = "web"
  }
}

# =============================================================================
# API SERVER (Private Subnet)
# =============================================================================

resource "google_compute_instance" "api" {
  name         = "vm-api-${var.deployment_id}"
  machine_type = "e2-micro"
  zone         = var.zone

  tags = ["api"]

  boot_disk {
    initialize_params {
      image = local.ubuntu_image
    }
  }

  network_interface {
    subnetwork = var.private_subnet_link
  }

  metadata = {
    "ssh-keys"      = local.ssh_metadata
    "startup-script" = templatefile("${path.module}/templates/api-init.sh", {
      admin_username = var.admin_username
    })
  }

  labels = {
    project = "networking-lab"
    role    = "api"
  }
}

# =============================================================================
# DATABASE SERVER (Database Subnet)
# =============================================================================

resource "google_compute_instance" "database" {
  name         = "vm-database-${var.deployment_id}"
  machine_type = "e2-micro"
  zone         = var.zone

  tags = ["db"]

  boot_disk {
    initialize_params {
      image = local.ubuntu_image
    }
  }

  network_interface {
    subnetwork = var.database_subnet_link
  }

  metadata = {
    "ssh-keys"      = local.ssh_metadata
    "startup-script" = templatefile("${path.module}/templates/database-init.sh", {
      admin_username = var.admin_username
    })
  }

  labels = {
    project = "networking-lab"
    role    = "database"
  }
}
