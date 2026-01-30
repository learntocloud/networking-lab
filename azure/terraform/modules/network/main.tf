# Network Module - Contains intentional misconfigurations for learning
# Students will need to fix these issues

resource "azurerm_virtual_network" "main" {
  name                = "vnet-networking-lab-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.vnet_cidr]

  tags = {
    project = "networking-lab"
  }
}

# =============================================================================
# SUBNETS
# BUG: Task 1 - Subnet CIDRs have issues (overlapping ranges)
# Students need to fix the CIDR blocks in variables.tf
# =============================================================================

resource "azurerm_subnet" "public" {
  name                 = "subnet-public"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.public_subnet_cidr]
}

resource "azurerm_subnet" "private" {
  name                 = "subnet-private"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_subnet_cidr]
}

resource "azurerm_subnet" "database" {
  name                 = "subnet-database"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.database_subnet_cidr]
}

# =============================================================================
# NAT GATEWAY (for private subnet outbound internet access)
# =============================================================================

resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "main" {
  name                = "nat-gateway-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# =============================================================================
# ROUTE TABLES
# BUG: Task 2 - NAT Gateway association is missing for private subnet
# Students need to fix routes.tf to associate NAT GW with private subnet
# =============================================================================

resource "azurerm_route_table" "public" {
  name                = "rt-public-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_route_table" "private" {
  name                = "rt-private-${var.deployment_id}"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_route_table" "database" {
  name                          = "rt-database-${var.deployment_id}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  disable_bgp_route_propagation = true
}

# Route table associations
resource "azurerm_subnet_route_table_association" "public" {
  subnet_id      = azurerm_subnet.public.id
  route_table_id = azurerm_route_table.public.id
}

resource "azurerm_subnet_route_table_association" "private" {
  subnet_id      = azurerm_subnet.private.id
  route_table_id = azurerm_route_table.private.id
}

resource "azurerm_subnet_route_table_association" "database" {
  subnet_id      = azurerm_subnet.database.id
  route_table_id = azurerm_route_table.database.id
}
