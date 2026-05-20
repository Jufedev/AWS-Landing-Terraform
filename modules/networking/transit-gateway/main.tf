resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each           = var.attachments
  subnet_ids         = each.value.subnet_ids
  transit_gateway_id = var.transit_gateway
  vpc_id             = each.value.vpc_id

  tags = {
    Name = each.key
  }
}
