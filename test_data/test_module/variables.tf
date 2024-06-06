variable "environment" {
  default = "development"
}
variable "region" {}
variable "role_arn" {}
variable "elastic_zone_id" {}
variable "bootstrap_mode" {}

variable "backend_subnet_ids" {}
variable "lb_subnet_ids" {}
variable "internet_gateway_id" {}
