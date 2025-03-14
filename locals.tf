locals {
  service_name   = var.cluster_name
  module_version = "3.0.1"

  default_module_tags = {
    environment : var.environment
    service : local.service_name
    account : data.aws_caller_identity.current.account_id
    created_by_module : "infrahouse/elasticsearch/aws"
    module_version : local.module_version
  }
  ami_name_pattern = contains(
    ["focal", "jammy"], var.ubuntu_codename
  ) ? "ubuntu/images/hvm-ssd/ubuntu-${var.ubuntu_codename}-*" : "ubuntu/images/hvm-ssd-gp3/ubuntu-${var.ubuntu_codename}-*"

}
