# Private hosted zone associated with the lab VPC. INC-4522 service records are absent.

data "aws_region" "current" {}

resource "aws_route53_zone" "internal" {
  name = "internal.test"

  vpc {
    vpc_id     = var.vpc_id
    vpc_region = data.aws_region.current.name
  }

  tags = {
    project = "networking-lab"
  }
}

