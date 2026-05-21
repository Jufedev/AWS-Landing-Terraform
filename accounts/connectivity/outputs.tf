output "transit_id" {
  value = aws_ec2_transit_gateway.this.id
}

output "attachment_ids" {
  value = module.transit.attachment_ids
}

output "internet_gw" {
  value = aws_internet_gateway.this.id
}

output "nat_gw" {
  value = aws_nat_gateway.this.id
}

output "spoke_vpc_ids" {
  value = { for name, id in module.vpc.vpc_ids : name => id if name != "IngresEgress" }
}

output "spoke_subnet_ids" {
  value = { for key, id in module.vpc.subnet_ids : key => id if !startswith(key, "IngresEgress.") }
}

output "spoke_route_table_ids" {
  value = { for key, id in module.vpc.route_table_ids : key => id if !startswith(key, "IngresEgress.") }
}
