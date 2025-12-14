variable "environment" {
  default = "development"
}
variable "region" {}
variable "role_arn" {
  default = null
}
variable "elastic_zone_id" {}
variable "bootstrap_mode" {}

variable "backend_subnet_ids" {}
variable "lb_subnet_ids" {}
