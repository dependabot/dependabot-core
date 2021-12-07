module "gitlab_ssh_without_protocol" {
  source     = "git@gitlab.com:cloudposse/terraform-aws-jenkins.git?ref=tags/0.4.0//some/dir"
  namespace  = var.namespace
  stage      = var.stage
  name       = var.name
  delimiter  = var.delimiter
  attributes = ["${compact(concat(var.attributes, list("origin")))}"]
  tags       = var.tags
}
