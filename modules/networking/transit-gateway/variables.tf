variable "transit_gateway" {
  description = "Id del transit a usar"
  type        = string
}

variable "attachments" {
  description = "Attachments"

  type = map(object({
    subnet_ids = list(string)
    vpc_id     = string
  }))
}
