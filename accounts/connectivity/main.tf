module "vpc" {
  source = "../../modules/networking/vpc"

  vpcs = {
    IngresEgress = var.cidr_ingress_egress
  }
}

module "transit" {
  source          = "../../modules/networking/transit-gateway"
  transit_gateway = aws_ec2_transit_gateway.this.id
  attachments     = module.vpc.tgw_attachments
}

locals {
  spoke_routes = flatten([
    for rt_key, rt_id in module.vpc.route_table_ids : [
      for spoke_name, spoke_cidr in var.spoke_cidrs : {
        key            = "${rt_key}.${spoke_name}"
        route_table_id = rt_id
        cidr           = spoke_cidr
      }
    ] if split(".", rt_key)[1] != "tgw"
  ])
}

resource "aws_ec2_transit_gateway" "this" {
  description = "Transit Gateway de la organizacion"
}

resource "aws_internet_gateway" "this" {
  vpc_id = module.vpc.vpc_ids["IngresEgress"]

  tags = {
    Name = "IngresEgress-igw"
  }
}

resource "aws_nat_gateway" "this" {
  availability_mode = "regional"
  connectivity_type = "public"
  vpc_id            = module.vpc.vpc_ids["IngresEgress"]

  tags = {
    Name = "IngresEgress-nat"
  }
}

resource "aws_route" "rTranstit" {
  for_each               = { for key, routetable_ids in module.vpc.route_table_ids : key => routetable_ids if split(".", key)[1] == "tgw" }
  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route" "rPublic" {
  for_each               = { for key, routetable_ids in module.vpc.route_table_ids : key => routetable_ids if split(".", key)[1] != "tgw" }
  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route" "rToSpoke" {
  for_each               = { for r in local.spoke_routes : r.key => r }
  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
}
