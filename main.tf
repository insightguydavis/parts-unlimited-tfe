provider "aws" {
  region     = "us-west-1"
  access_key = "AKIARRMB547SKGEGSACX"
  secret_key = "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"
}

provider "aws" {
  region     = "us-east-1"
  alias      = "us-east-1"
  access_key = "AKIARRMB547SKGEGSACX"
  secret_key = "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"
}

provider "aws" {
  region     = "us-west-1"
  alias      = "us-west-1"
  access_key = "AKIARRMB547SKGEGSACX"
  secret_key = "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"
}

data "aws_availability_zones" "east-azs" {
  provider = aws.us-east-1
  state    = "available"
}

module "east-vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "east-vpc"
  cidr = "10.0.0.0/16"

  # Grab entire set of names if needed from data source
  azs = data.aws_availability_zones.east-azs.names

  # Use cidrsubnet function with for_each to create the right number of subnets
  public_subnets = [for num in var.netnums : cidrsubnet("10.0.0.0/16", 8, num)]

  providers = {
    aws = aws.us-east-1
  }
}

data "aws_availability_zones" "west-azs" {
  provider = aws.us-west-1
  state    = "available"
}

module "west-vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "west-vpc"
  cidr = "10.1.0.0/16"

  # Grab entire set of names if needed from data source
  azs = data.aws_availability_zones.west-azs.names

  # Use a function with for_each to create the right number of subnets
  public_subnets = [
    for num in var.netnums :
    cidrsubnet("10.1.0.0/16", 8, num)
  ]

  providers = {
    aws = aws.us-west-1
  }
}

resource "aws_vpc_peering_connection" "peer" {
  provider    = aws.us-east-1
  vpc_id      = module.east-vpc.vpc_id
  peer_vpc_id = module.west-vpc.vpc_id
  peer_region = "us-west-1"
  auto_accept = false
}

# Accepter's side of the connection.
resource "aws_vpc_peering_connection_accepter" "peer" {
  provider                  = aws.us-west-1
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
  auto_accept               = true
}

resource "aws_default_security_group" "east-vpc" {
  provider = aws.us-east-1
  vpc_id   = module.east-vpc.vpc_id

  ingress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_default_security_group" "west-vpc" {
  provider = aws.us-west-1
  vpc_id   = module.west-vpc.vpc_id

  ingress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

locals {
  east-routes = setproduct(module.east-vpc.public_route_table_ids, module.west-vpc.public_subnets_cidr_blocks)
  west-routes = setproduct(module.west-vpc.public_route_table_ids, module.east-vpc.public_subnets_cidr_blocks)
}

resource "aws_route" "east-vpc" {
  provider = aws.us-east-1
  count    = length(local.east-routes)

  # Need to create a route for every combination of route_table_id 
  # on module.east-vpc.public_route_table_ids with every cidr_block 
  # on module.west-vpc.public_cidr_blocks. Look into setproduct function. 
  # Using setproduct, element, and length, this can be done dynamically

  route_table_id            = element(local.east-routes[count.index], 0)
  destination_cidr_block    = element(local.east-routes[count.index], 1)
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
}

resource "aws_route" "west-vpc" {
  provider = aws.us-west-1
  count    = length(local.west-routes)

  # Need to create a route for every combination of route_table_id 
  # on module.east-vpc.public_route_table_ids with every cidr_block 
  # on module.west-vpc.public_cidr_blocks. Look into setproduct function. 
  # Using setproduct, element, and length, this can be done dynamically

  route_table_id            = element(local.west-routes[count.index], 0)
  destination_cidr_block    = element(local.west-routes[count.index], 1)
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
}

module "terraform_enterprise" {
  source = "./terraform-enterprise-aws"

  friendly_name_prefix    = "insight-guy"
  common_tags             = {}
  tfe_hostname            = "insight-guy.com"
  tfe_license_file_path   = "./terraform-chip.rli"
  tfe_initial_admin_email = "guy.davis@insight.com"
  tfe_initial_admin_pw    = "pass@word1"
  tfe_initial_org_name    = "Insight Enterprises"
  tfe_initial_org_email   = "guy.davis@insight.com"
  tls_certificate_arn     = "arn:aws:acm:us-west-1:106036062180:certificate/0b6034db-0260-4841-8c25-3105ed519e1f"
  vpc_id                  = module.west-vpc.vpc_id
  alb_subnet_ids          = [module.west-vpc.public_subnets[0], module.west-vpc.public_subnets[1]]
  rds_subnet_ids          = [module.west-vpc.public_subnets[1], module.west-vpc.public_subnets[2]]
  ec2_subnet_ids          = [module.west-vpc.public_subnets[1], module.west-vpc.public_subnets[2]]
}
