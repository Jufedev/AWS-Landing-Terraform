variable "vpcs" {
  description = "Mapa de VPCs"

  type = map(object({
    cidr_block = string
    subnets = map(object({
      cidr_block = string
      az         = string
    }))
  }))
}
