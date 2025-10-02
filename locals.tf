locals {
  service_name   = var.cluster_name
  module_version = "3.11.0"

  default_module_tags = {
    environment : var.environment
    service : local.service_name
    account : data.aws_caller_identity.current.account_id
    created_by_module : "infrahouse/elasticsearch/aws"
  }
  ami_name_pattern_pro = "ubuntu-pro-server/images/hvm-ssd-gp3/ubuntu-${var.ubuntu_codename}-*"

}
