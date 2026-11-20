module "database" {
  source  = "registry.example.org/Namespace/RDS/aws"
  version = "1.0.0"
}

module "cache" {
  source  = "Registry.Example.ORG/namespace/Redis/aws"
  version = "2.0.0"
}
