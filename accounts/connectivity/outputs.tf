
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
