terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.55.0"
    }
  }
}

# Terraform >= 1.15 allows a `const` input variable in a module source address, so the ref
# here is not a literal and carries no readable version.
variable "module_version" {
  type    = string
  default = "v0.6.0"
}

module "interpolated" {
  source = "git::https://github.com/example/modules.git//modules/thing?ref=${var.module_version}"
}

module "literal" {
  source = "git::https://github.com/example/modules.git//modules/other?ref=v1.2.3"
}
