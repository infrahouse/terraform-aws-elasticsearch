locals {
  service_name   = var.cluster_name
  module_version = "2.1.5"

  default_module_tags = {
    environment : var.environment
    service : local.service_name
    account : data.aws_caller_identity.current.account_id
    created_by_module : "infrahouse/elasticsearch/aws"
    module_version : local.module_version
  }
}
