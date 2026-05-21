variable "aws_region" {
  description = "Region donde se depliega la carga"
  type        = string
}

variable "project_name" {
  description = "Nombre del proyecto para Tags"
  type        = string
}

variable "s3_state" {
  description = "Nombre del S3 donde se va a almacenar el estado"
  type        = string
}

variable "deploy_role_arn" {
  description = "Rol para la cuenta de despliegue"
  type        = string
}

variable "cidr_ingress_egress" {
  description = "Valor de la VPC ingress/egress"
  type = object({
    cidr_block = string
    subnets = map(object({
      cidr_block = string
      az         = string
    }))
  })
}

variable "spoke_vpcs" {
  description = "Mapa de VPCs spoke a crear dinamicamente (dev, prod, etc)"
  type = map(object({
    cidr_block = string
    subnets = map(object({
      cidr_block = string
      az         = string
    }))
  }))
}

variable "workloads_account_ids" {
  description = "IDs de las cuentas de Workloads para compartir subnets via RAM (ej: { dev = \"123...\", prod = \"456...\" })"
  type        = map(string)
}
