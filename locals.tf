locals {
  service_name   = var.cluster_name
  module_version = "3.12.0"

  default_module_tags = {
    environment : var.environment
    service : local.service_name
    account : data.aws_caller_identity.current.account_id
    created_by_module : "infrahouse/elasticsearch/aws"
  }
  ami_name_pattern_pro = "ubuntu-pro-server/images/hvm-ssd-gp3/ubuntu-${var.ubuntu_codename}-*"

  log_group_name = "/elasticsearch/${var.environment}/${var.cluster_name}"
}
