terraform {
  required_version = ">= 0.12"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "0.1.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}
