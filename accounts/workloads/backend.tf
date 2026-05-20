terraform {
  backend "s3" {
    bucket       = var.s3_state
    key          = "${terraform.workspace}-workload/terraform.tfstate"
    region       = var.aws_region
    use_lockfile = true
    encrypt      = true
  }
}
