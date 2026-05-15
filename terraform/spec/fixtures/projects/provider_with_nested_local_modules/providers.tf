terraform {
  required_version = ">= 1.7.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.75.1"
    }
  }
}
