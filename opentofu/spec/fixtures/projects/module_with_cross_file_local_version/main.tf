module "consul" {
  source  = "hashicorp/consul/aws"
  version = local.module_version
}
