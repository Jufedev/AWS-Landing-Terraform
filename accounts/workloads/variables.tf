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

variable "cidrs_spokes" {
  description = "Valores defecto del las cargas"
  type = map(object({
    cidr_block = string
    subnets = map(object({
      cidr_block = string
      az         = string
    }))
  }))
}
