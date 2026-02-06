# Compute Module - EC2 instances for the networking lab

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "lab" {
  key_name   = "netlab-key-${var.deployment_id}"
  public_key = tls_private_key.ssh.public_key_openssh
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# =============================================================================
# BASTION HOST (Public Subnet)
# =============================================================================

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.bastion_sg_id]
  key_name                    = aws_key_pair.lab.key_name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/templates/bastion-init.sh", {
    ssh_private_key = tls_private_key.ssh.private_key_pem
    ssh_public_key  = tls_private_key.ssh.public_key_openssh
    admin_username  = var.admin_username
  })

  tags = {
    Name    = "vm-bastion-${var.deployment_id}"
    project = "networking-lab"
    role    = "bastion"
  }
}

resource "aws_eip" "bastion" {
  domain = "vpc"

  tags = {
    Name    = "eip-bastion-${var.deployment_id}"
    project = "networking-lab"
  }
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}

# =============================================================================
# WEB SERVER (Private Subnet + Public IP for HTTP/HTTPS testing)
# =============================================================================

resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = var.private_subnet_id
  vpc_security_group_ids      = [var.web_sg_id]
  key_name                    = aws_key_pair.lab.key_name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/templates/web-init.sh", {
    admin_username = var.admin_username
    ssh_public_key = tls_private_key.ssh.public_key_openssh
  })

  tags = {
    Name    = "vm-web-${var.deployment_id}"
    project = "networking-lab"
    role    = "web"
  }
}

resource "aws_eip" "web" {
  domain = "vpc"

  tags = {
    Name    = "eip-web-${var.deployment_id}"
    project = "networking-lab"
  }
}

resource "aws_eip_association" "web" {
  instance_id   = aws_instance.web.id
  allocation_id = aws_eip.web.id
}

# =============================================================================
# API SERVER (Private Subnet)
# =============================================================================

resource "aws_instance" "api" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = var.private_subnet_id
  vpc_security_group_ids      = [var.api_sg_id]
  key_name                    = aws_key_pair.lab.key_name
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/templates/api-init.sh", {
    admin_username = var.admin_username
    ssh_public_key = tls_private_key.ssh.public_key_openssh
  })

  tags = {
    Name    = "vm-api-${var.deployment_id}"
    project = "networking-lab"
    role    = "api"
  }
}

# =============================================================================
# DATABASE SERVER (Database Subnet)
# =============================================================================

resource "aws_instance" "database" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = var.database_subnet_id
  vpc_security_group_ids      = [var.db_sg_id]
  key_name                    = aws_key_pair.lab.key_name
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/templates/database-init.sh", {
    admin_username = var.admin_username
    ssh_public_key = tls_private_key.ssh.public_key_openssh
  })

  tags = {
    Name    = "vm-database-${var.deployment_id}"
    project = "networking-lab"
    role    = "database"
  }
}
