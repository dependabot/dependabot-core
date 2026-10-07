terraform {
  required_version = ">= 0.12"

  required_providers {
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
