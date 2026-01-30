# Compute Module - VMs for the networking lab

# Generate SSH key for VM access
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# =============================================================================
# BASTION HOST (Public Subnet)
# =============================================================================

resource "azurerm_public_ip" "bastion" {
  name                = "pip-bastion-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "bastion" {
  name                = "nic-bastion-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.public_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.bastion.id
  }
}

resource "azurerm_network_interface_security_group_association" "bastion" {
  network_interface_id      = azurerm_network_interface.bastion.id
  network_security_group_id = var.bastion_nsg_id
}

resource "azurerm_linux_virtual_machine" "bastion" {
  name                = "vm-bastion-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = "Standard_B1s"
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.bastion.id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/templates/bastion-init.sh", {
    ssh_private_key = tls_private_key.ssh.private_key_pem
    admin_username  = var.admin_username
  }))

  tags = {
    project = "networking-lab"
    role    = "bastion"
  }
}

# =============================================================================
# WEB SERVER (Private Subnet + Public IP for HTTP/HTTPS testing)
# =============================================================================

resource "azurerm_public_ip" "web" {
  name                = "pip-web-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "web" {
  name                = "nic-web-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.private_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.web.id
  }
}

resource "azurerm_network_interface_security_group_association" "web" {
  network_interface_id      = azurerm_network_interface.web.id
  network_security_group_id = var.web_nsg_id
}

resource "azurerm_linux_virtual_machine" "web" {
  name                = "vm-web-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = "Standard_B1s"
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.web.id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/templates/web-init.sh", {
    admin_username = var.admin_username
  }))

  tags = {
    project = "networking-lab"
    role    = "web"
  }
}

# =============================================================================
# API SERVER (Private Subnet)
# =============================================================================

resource "azurerm_network_interface" "api" {
  name                = "nic-api-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.private_subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "api" {
  network_interface_id      = azurerm_network_interface.api.id
  network_security_group_id = var.api_nsg_id
}

resource "azurerm_linux_virtual_machine" "api" {
  name                = "vm-api-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = "Standard_B1s"
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.api.id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/templates/api-init.sh", {
    admin_username = var.admin_username
  }))

  tags = {
    project = "networking-lab"
    role    = "api"
  }
}

# =============================================================================
# DATABASE SERVER (Database Subnet)
# =============================================================================

resource "azurerm_network_interface" "database" {
  name                = "nic-database-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.database_subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "database" {
  network_interface_id      = azurerm_network_interface.database.id
  network_security_group_id = var.database_nsg_id
}

resource "azurerm_linux_virtual_machine" "database" {
  name                = "vm-database-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = "Standard_B1s"
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.database.id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/templates/database-init.sh", {
    admin_username = var.admin_username
  }))

  tags = {
    project = "networking-lab"
    role    = "database"
  }
}
