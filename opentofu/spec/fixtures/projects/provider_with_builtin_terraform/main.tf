terraform {
  required_version = ">= 1.0"

  required_providers {
    terraform = {
      source  = "terraform.io/builtin/terraform"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 2.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "3.37.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

