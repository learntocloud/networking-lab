# Security Groups (intentional misconfigurations for learning)
#
# Security groups are stateful and allow-only: every attached group's rules are
# additive, and there are no deny rules or priorities. INC-4523 and INC-4524 are
# repaired with the AWS CLI, not by editing these definitions.

resource "aws_security_group" "bastion" {
  name        = "netlab-bastion-${var.deployment_id}"
  description = "Bastion security group"
  vpc_id      = aws_vpc.main.id

  revoke_rules_on_delete = true

  timeouts {
    delete = "2m"
  }

  ingress {
    description = "SSH from anywhere (INC-4524)"
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
    description = "SSH from anywhere (INC-4524)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP from anywhere (INC-4524)"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # INC-4523: no egress to the API on TCP 8080.
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
    description = "SSH from anywhere (INC-4524)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # INC-4523: no ingress on TCP 8080 from the web tier, and no egress to the
  # database on TCP 5432. Package installation only needs HTTP/HTTPS egress;
  # Amazon-provided DNS is not filtered by security groups.

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
    description = "SSH from anywhere (INC-4524)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Postgres from anywhere (INC-4524)"
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
