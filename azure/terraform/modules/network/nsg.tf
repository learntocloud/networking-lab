# =============================================================================
# NETWORK SECURITY GROUPS
# BUG: Task 5 & 6 - NSG rules are misconfigured
#
# Issues for students to find and fix:
# - Task 5: API server port 8080 not properly allowed from web server
# - Task 5: Database port 5432 blocked even from API server
# - Task 6: SSH open to entire internet (should be bastion only)
# - Task 6: Overly permissive rules that should be locked down
# =============================================================================

# -----------------------------------------------------------------------------
# Bastion NSG - Allows SSH from internet (this is intentional for bastion)
# -----------------------------------------------------------------------------
resource "azurerm_network_security_group" "bastion" {
  name                = "nsg-bastion-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location

  # Allow SSH from internet to bastion (this is correct)
  security_rule {
    name                       = "allow-ssh-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    project = "networking-lab"
  }
}

# -----------------------------------------------------------------------------
# Web Server NSG
# BUG Task 6: SSH is open to internet instead of bastion only
# -----------------------------------------------------------------------------
resource "azurerm_network_security_group" "web" {
  name                = "nsg-web-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location

  # Allow HTTP from internet
  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow HTTPS from internet
  security_rule {
    name                       = "allow-https"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # BUG Task 6: SSH open to internet! Should only allow from bastion/public subnet
  security_rule {
    name                       = "allow-ssh"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"  # BUG: Should be "10.0.1.0/24" (public subnet only)
    destination_address_prefix = "*"
  }

  # BUG Task 6: ICMP from anywhere - unnecessary exposure
  security_rule {
    name                       = "allow-icmp"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"  # BUG: Should be VNet only "10.0.0.0/16"
    destination_address_prefix = "*"
  }

  tags = {
    project = "networking-lab"
  }
}

# -----------------------------------------------------------------------------
# API Server NSG
# BUG Task 5: Port 8080 has wrong priority, blocked by earlier deny rule
# -----------------------------------------------------------------------------
resource "azurerm_network_security_group" "api" {
  name                = "nsg-api-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location

  # BUG Task 5: Deny rule has LOWER priority number (higher precedence) than allow!
  # This blocks the API traffic before the allow rule can permit it
  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 100  # BUG: This runs BEFORE the allow rule at 200!
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # This allow rule never gets evaluated because deny rule has lower priority number!
  security_rule {
    name                       = "allow-api-from-web"
    priority                   = 200  # BUG: Higher number = lower precedence. Move to 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "10.0.2.0/24"  # private subnet (web server)
    destination_address_prefix = "*"
  }

  # SSH - same bug as web server
  security_rule {
    name                       = "allow-ssh"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"  # BUG Task 6: Should be public subnet only
    destination_address_prefix = "*"
  }

  tags = {
    project = "networking-lab"
  }
}

# -----------------------------------------------------------------------------
# Database NSG
# BUG Task 5: PostgreSQL port blocked from API server
# BUG Task 6: Port open to too wide a range
# -----------------------------------------------------------------------------
resource "azurerm_network_security_group" "database" {
  name                = "nsg-database-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location

  # BUG Task 5: Source should be API server subnet, not entire VNet
  # BUG Task 5: This rule is DENY instead of ALLOW!
  security_rule {
    name                       = "postgres-access"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Deny"  # BUG: Should be "Allow"!
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "10.0.0.0/16"  # BUG Task 6: Too wide, should be API subnet "10.0.2.0/24"
    destination_address_prefix = "*"
  }

  # BUG Task 6: SSH from anywhere
  security_rule {
    name                       = "allow-ssh"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"  # BUG: Should be public subnet only (bastion)
    destination_address_prefix = "*"
  }

  tags = {
    project = "networking-lab"
  }
}
