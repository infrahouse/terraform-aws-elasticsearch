resource "random_password" "elastic" {
  length = 21
}

module "elastic-password" {
  source  = "registry.infrahouse.com/infrahouse/secret/aws"
  version = "1.1.1"

  environment        = var.environment
  secret_description = "Password for user elastic in cluster ${var.cluster_name}"
  secret_name        = "${var.cluster_name}-elastic-password"
  secret_value       = random_password.elastic.result
  readers = concat(
    var.secret_elastic_readers,
    [
      module.elastic_cluster.instance_role_arn,

    ],
    var.bootstrap_mode ? [] : [module.elastic_cluster_data[0].instance_role_arn],
  )
}

resource "random_password" "kibana_system" {
  length  = 21
  special = false
}



module "kibana_system-password" {
  source  = "registry.infrahouse.com/infrahouse/secret/aws"
  version = "1.1.1"
  # insert the 2 required variables here
  environment        = var.environment
  secret_description = "Password for user kibana_system in cluster ${var.cluster_name}"
  secret_name        = "${var.cluster_name}-kibana_system-password"
  secret_value       = random_password.kibana_system.result
  readers = concat(
    var.secret_elastic_readers,
    [
      module.elastic_cluster.instance_role_arn,
    ],
    var.bootstrap_mode ? [] : [module.elastic_cluster_data[0].instance_role_arn],
  )

}
