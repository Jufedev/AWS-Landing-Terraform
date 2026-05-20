locals {
  config = var.cidrs_spokes
}

locals {
  current = local.config[terraform.workspace]
}

data "terraform_remote_state" "connectivity" {
  backend = "s3"
  config = {
    bucket = var.s3_state
    key    = "accounts/connectivity/terraform.tfstate"
    region = var.aws_region
  }
}

module "vpc" {
  source = "../../modules/networking/vpc"

  vpcs = {
    (terraform.workspace) = local.current
  }
}

module "transit_attach" {
  source          = "../../modules/networking/transit-gateway"
  transit_gateway = data.terraform_remote_state.connectivity.outputs.transit_id
  attachments     = module.vpc.tgw_attachments
}

resource "aws_route" "r" {
  for_each               = { for key, routetable_ids in module.vpc.route_table_ids : key => routetable_ids if split(".", key)[1] != "tgw" }
  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = data.terraform_remote_state.connectivity.outputs.transit_id
}
