# Security Groups (intentional misconfigurations for learning)

resource "aws_security_group" "bastion" {
  name        = "netlab-bastion-${var.deployment_id}"
  description = "Bastion security group"
  vpc_id      = aws_vpc.main.id

  revoke_rules_on_delete = true

  timeouts {
    delete = "2m"
  }

  ingress {
    description = "SSH from anywhere (intentional)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "sg-bastion-${var.deployment_id}"
    project = "networking-lab"
  }
}

resource "aws_security_group" "web" {
  name        = "netlab-web-${var.deployment_id}"
  description = "Web security group"
  vpc_id      = aws_vpc.main.id

  revoke_rules_on_delete = true

  timeouts {
    delete = "2m"
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from anywhere (intentional)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP from anywhere (intentional)"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound web only"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound HTTPS only"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "sg-web-${var.deployment_id}"
    project = "networking-lab"
  }
}

resource "aws_security_group" "api" {
  name        = "netlab-api-${var.deployment_id}"
  description = "API security group"
  vpc_id      = aws_vpc.main.id

  revoke_rules_on_delete = true

  timeouts {
    delete = "2m"
  }

  ingress {
    description = "SSH from anywhere (intentional)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Intentional break: missing inbound 8080 from web

  egress {
    description = "Allow outbound web only"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound HTTPS only"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "sg-api-${var.deployment_id}"
    project = "networking-lab"
  }
}

resource "aws_security_group" "database" {
  name        = "netlab-database-${var.deployment_id}"
  description = "Database security group"
  vpc_id      = aws_vpc.main.id

  revoke_rules_on_delete = true

  timeouts {
    delete = "2m"
  }

  ingress {
    description = "SSH from anywhere (intentional)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Postgres from anywhere (intentional)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "sg-database-${var.deployment_id}"
    project = "networking-lab"
  }
}
