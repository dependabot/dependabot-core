module "github_ssh_without_protocol" {
  source                       = "git@github.com:cloudposse/terraform-aws-jenkins.git?ref=0.4.1"
  namespace                    = var.namespace
  stage                        = var.stage
  name                         = var.name
  delimiter                    = var.delimiter
  attributes                   = [compact(concat(var.attributes, ["origin"]))]
  tags                         = var.tags
  availability_zone            = ""
  loadbalancer_certificate_arn = ""
  public_subnets               = []
}
