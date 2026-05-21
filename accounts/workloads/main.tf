data "terraform_remote_state" "connectivity" {
  backend = "s3"
  config = {
    bucket = var.s3_state
    key    = "accounts/connectivity/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  spoke_subnet_ids     = data.terraform_remote_state.connectivity.outputs.spoke_subnet_ids
  spoke_vpc_ids        = data.terraform_remote_state.connectivity.outputs.spoke_vpc_ids
  spoke_route_table_ids = data.terraform_remote_state.connectivity.outputs.spoke_route_table_ids

  current_subnet_ids = {
    for key, id in local.spoke_subnet_ids : split(".", key)[1] => id
    if startswith(key, "${terraform.workspace}.")
  }

  current_vpc_id = local.spoke_vpc_ids[terraform.workspace]
}
