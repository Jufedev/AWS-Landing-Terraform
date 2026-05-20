output "attachment_ids" {
  value = { for key, val in aws_ec2_transit_gateway_vpc_attachment.this : key => val.id }
}
