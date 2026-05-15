locals {
  module_version = "0.1.0"
}

module "consul" {
  source  = "hashicorp/consul/aws"
  version = "${local.module_version}"
}
