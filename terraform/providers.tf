# The providers.tf file configures the Terraform providers that will be needed to build the infrastructure. In our case, we use the aws, kubernetes and helm providers:

provider "aws" {
  default_tags {
    tags = local.tags
  }
  region = "eu-west-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.67.0"
    }
  }

  required_version = ">= 1.4.2"
}
