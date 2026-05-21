locals {
  subnets = flatten([
    for vpc_name, vpc in var.vpcs : [
      for subnet_name, subnet in vpc.subnets : {
        key         = "${vpc_name}.${subnet_name}"
        vpc_name    = vpc_name
        subnet_name = subnet_name
        cidr_block  = subnet.cidr_block
        az          = subnet.az
      }
    ]
  ])

  subnets_by_key = { for snet in local.subnets : snet.key => snet }

  subnets_by_type = { for key, val in aws_subnet.this : "${split(".", key)[0]}.${split("-", split(".", key)[1])[0]}" => val.id... }

  tgw_attachments = {
    for key, subnet_ids in local.subnets_by_type :
    split(".", key)[0] => {
      subnet_ids = subnet_ids
      vpc_id     = aws_vpc.this[split(".", key)[0]].id
    } if split(".", key)[1] == "tgw"
  }
}

resource "aws_vpc" "this" {
  for_each = var.vpcs

  cidr_block = each.value.cidr_block

  tags = {
    Name = each.key,
  }
}

resource "aws_subnet" "this" {
  for_each = local.subnets_by_key

  vpc_id            = aws_vpc.this[each.value.vpc_name].id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.az

  tags = {
    Name = "${each.value.vpc_name}-${each.value.subnet_name}"
  }
}

resource "aws_route_table" "this" {
  for_each = local.subnets_by_type

  vpc_id = aws_vpc.this[split(".", each.key)[0]].id

  tags = {
    Name = "rt-${each.key}"
  }
}

resource "aws_ec2_tag" "default_rt" {
  for_each    = aws_vpc.this
  resource_id = each.value.default_route_table_id
  key         = "Name"
  value       = "rt-${each.key}-main"
}

resource "aws_route_table_association" "this" {
  for_each = aws_subnet.this

  subnet_id      = each.value.id
  route_table_id = aws_route_table.this["${split(".", each.key)[0]}.${split("-", split(".", each.key)[1])[0]}"].id
}
