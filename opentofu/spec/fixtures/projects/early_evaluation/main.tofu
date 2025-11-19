variable "module_name" {
  type    = string
  default = "module_name"
}

module "interpolated_module" {
  source = "./${var.module_name}"
}
