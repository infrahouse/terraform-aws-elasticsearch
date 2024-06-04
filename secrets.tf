resource "random_password" "elastic" {
  length = 21
}

resource "random_password" "kibana_system" {
  length  = 21
  special = false
}

module "secret_kibana_system" {
  source             = "registry.infrahouse.com/infrahouse/secret/aws"
  version            = "0.4.0"
  secret_description = "Password for user kibana_system in cluster ${var.cluster_name}"
  secret_name        = "${var.cluster_name}-kibana_system-password"
  secret_value       = random_password.kibana_system.result
}

module "secret_elastic" {
  source             = "registry.infrahouse.com/infrahouse/secret/aws"
  version            = "0.4.0"
  secret_description = "Password for user elastic in cluster ${var.cluster_name}"
  secret_name        = "${var.cluster_name}-elastic-password"
  secret_value       = random_password.elastic.result
  readers            = var.secret_elastic_readers
}
