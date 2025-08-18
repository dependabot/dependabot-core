terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

module "vpc" {
  source  = "company/vpc/aws"
  version = "1.0.0"

  cidr_block           = "10.0.0.0/16"
  region               = "us-west-2"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

module "security" {
  source  = "company/security/aws"
  version = "0.5.0"

  vpc_id = module.vpc.vpc_id
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}
