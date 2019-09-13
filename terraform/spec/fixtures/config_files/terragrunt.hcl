terraform {
  source = "git::git@github.com:gruntwork-io/modules-example.git//consul?ref=v0.0.2"

  after_hook "provider" {
    commands = ["init-from-module"]
    execute  = ["cp", "${get_terragrunt_dir()}/../../some_module.tf", "."]
  }

  extra_arguments "config" {
    commands = get_terraform_commands_that_need_vars()

    required_var_files = [
      "${get_terragrunt_dir()}/../../defaults.tfvars",
    ]

    arguments = [
      "-var", "my_var=${get_terragrunt_dir()}/../../some_file.txt"
    ]
  }
}
