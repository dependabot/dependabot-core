terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.37.0"
    }
  }

}
