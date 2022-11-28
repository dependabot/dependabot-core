module "consul" {
  source = "hashicorp/consul/aws"
  version = "0.1.0"
}

module "vpc" {
  source = "app.terraform.io/example_corp/vpc/aws"
  version = "0.9.3"
}

module "rds" {
  source = "terraform-aws-modules/rds/aws"
  version = "~> 1.0.0"
}

module "members-github" {
  source = "devops-workflow/members/github"
}
