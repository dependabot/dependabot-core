module "merged" {
  source = "mongodb/ecs-task-definition/aws//modules/merge"

  container_definitions = [
    var.web_container_definition
    "${module.xray.container_definitions}",
    module.reverse_proxy.container_definitions
    module.datadog.container_definitions
  ]
}
