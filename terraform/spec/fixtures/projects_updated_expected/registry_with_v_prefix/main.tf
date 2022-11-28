module "consul" {
  source = "hashicorp/consul/aws"
  version = "0.3.1"
}

module "vpc" {
  source = "app.terraform.io/example_corp/vpc/aws"
  version = "v0.9.3"
}

module "rds" {
  source = "terraform-aws-modules/rds/aws"
  version = "~> v1.0.0"
}

module "members-github" {
  source = "devops-workflow/members/github"
}

module "merged" {
  source = "mongodb/ecs-task-definition/aws//modules/merge"

  container_definitions = [
    "${var.web_container_definition}",
    "${module.xray.container_definitions}",
    "${module.reverse_proxy.container_definitions}",
    "${module.datadog.container_definitions}",
  ]
}
