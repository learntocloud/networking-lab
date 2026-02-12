resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "vpc-networking-lab-${var.deployment_id}"
    project = "networking-lab"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "igw-networking-lab-${var.deployment_id}"
    project = "networking-lab"
  }
}

data "aws_availability_zones" "available" {
  state         = "available"
  exclude_names = ["us-east-1e"]
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = {
    Name    = "subnet-public"
    project = "networking-lab"
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[1]

  tags = {
    Name    = "subnet-private"
    project = "networking-lab"
  }
}

resource "aws_subnet" "database" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.database_subnet_cidr
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[2]

  tags = {
    Name    = "subnet-database"
    project = "networking-lab"
  }
}

# =============================================================================
# NAT GATEWAY (intentionally missing private route table route)
# =============================================================================

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name    = "eip-nat-${var.deployment_id}"
    project = "networking-lab"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name    = "nat-gateway-${var.deployment_id}"
    project = "networking-lab"
  }
}

# =============================================================================
# ROUTE TABLES
# =============================================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name    = "rt-public-${var.deployment_id}"
    project = "networking-lab"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # Intentional break: missing 0.0.0.0/0 -> NAT Gateway route

  tags = {
    Name    = "rt-private-${var.deployment_id}"
    project = "networking-lab"
  }
}

resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name    = "rt-database-${var.deployment_id}"
    project = "networking-lab"
  }
}

# Route table associations
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "database" {
  subnet_id      = aws_subnet.database.id
  route_table_id = aws_route_table.database.id
}

# =============================================================================
# DATABASE NETWORK ACL (intentional deny for 5432)
# =============================================================================

resource "aws_network_acl" "database" {
  vpc_id = aws_vpc.main.id

  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 5432
    to_port    = 5432
  }

  ingress {
    rule_no    = 200
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name    = "nacl-database-${var.deployment_id}"
    project = "networking-lab"
  }
}

resource "aws_network_acl_association" "database" {
  subnet_id      = aws_subnet.database.id
  network_acl_id = aws_network_acl.database.id
}
