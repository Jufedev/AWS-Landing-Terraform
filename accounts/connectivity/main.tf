locals {
  all_vpcs = merge(
    { IngresEgress = var.cidr_ingress_egress },
    var.spoke_vpcs
  )

  spoke_cidrs = { for name, vpc in var.spoke_vpcs : name => vpc.cidr_block }

  spoke_routes = flatten([
    for rt_key, rt_id in module.vpc.route_table_ids : [
      for spoke_name, spoke_cidr in local.spoke_cidrs : {
        key            = "${rt_key}.${spoke_name}"
        route_table_id = rt_id
        cidr           = spoke_cidr
      }
    ] if split(".", rt_key)[0] == "IngresEgress" && split(".", rt_key)[1] != "tgw"
  ])

  spoke_app_db_subnet_arns = {
    for key, arn in module.vpc.subnet_arns : key => arn
    if !startswith(key, "IngresEgress.") && !endswith(split(".", key)[1], "tgw")
  }
}

module "vpc" {
  source = "../../modules/networking/vpc"

  vpcs = local.all_vpcs
}

module "transit" {
  source          = "../../modules/networking/transit-gateway"
  transit_gateway = aws_ec2_transit_gateway.this.id
  attachments     = module.vpc.tgw_attachments
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

resource "aws_route" "tgw_to_nat" {
  for_each               = { for key, id in module.vpc.route_table_ids : key => id if split(".", key)[0] == "IngresEgress" && split(".", key)[1] == "tgw" }
  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route" "public_to_igw" {
  for_each               = { for key, id in module.vpc.route_table_ids : key => id if split(".", key)[0] == "IngresEgress" && split(".", key)[1] != "tgw" }
  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route" "hub_to_spoke" {
  for_each               = { for r in local.spoke_routes : r.key => r }
  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
}

resource "aws_route" "spoke_to_tgw" {
  for_each = {
    for key, id in module.vpc.route_table_ids : key => id
    if !startswith(key, "IngresEgress.") && split(".", key)[1] != "tgw"
  }
  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
}

resource "aws_ram_resource_share" "spoke" {
  for_each                  = var.spoke_vpcs
  name                      = "${each.key}-subnets"
  allow_external_principals = false
}

resource "aws_ram_resource_association" "subnets" {
  for_each           = local.spoke_app_db_subnet_arns
  resource_arn       = each.value
  resource_share_arn = aws_ram_resource_share.spoke[split(".", each.key)[0]].arn
}

resource "aws_ram_principal_association" "workloads" {
  for_each           = var.workloads_account_ids
  principal          = each.value
  resource_share_arn = aws_ram_resource_share.spoke[each.key].arn
}

