provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn = var.deploy_role_arn
  }

  default_tags {
    tags = {
      Project     = var.project_name,
      Environment = terraform.workspace
    }
  }
}
