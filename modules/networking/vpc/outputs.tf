output "vpc_ids" {
  value = { for key, val in aws_vpc.this : key => val.id }
}

output "vpc_cidr_blocks" {
  value = { for key, val in aws_vpc.this : key => val.cidr_block }
}

output "subnet_ids" {
  value = { for key, val in aws_subnet.this : key => val.id }
}

output "tgw_attachments" {
  value = local.tgw_attachments
}

output "route_table_ids" {
  value = { for key, val in aws_route_table.this : key => val.id }
}
