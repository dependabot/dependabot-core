terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

module "vpc" {
  source  = "registry.terraform.io:443/terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name = "my-vpc"
  cidr = "10.0.0.0/16"
}
