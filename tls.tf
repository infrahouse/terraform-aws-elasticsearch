# CA
resource "tls_private_key" "ca_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Generate CA Certificate
resource "tls_self_signed_cert" "ca_cert" {
  private_key_pem   = tls_private_key.ca_key.private_key_pem
  is_ca_certificate = true

  subject {
    common_name  = "InfraHouseCA"
    organization = "InfraHouse"
  }

  validity_period_hours = 24 * 356 * 100
  allowed_uses = [
    "cert_signing",
    "crl_signing"
  ]
}


module "ca_key_secret" {
  source             = "registry.infrahouse.com/infrahouse/secret/aws"
  version            = "~> 1.0"
  environment        = var.environment
  service_name       = local.service_name
  secret_description = "CA secret key for cluster ${var.cluster_name}"
  secret_name_prefix = "${var.cluster_name}-ca-key-"
  secret_value       = tls_private_key.ca_key.private_key_pem
  readers = concat(
    [
      module.elastic_cluster.instance_role_arn,
    ],
    var.bootstrap_mode ? [] : [
      module.elastic_cluster_data[0].instance_role_arn,
    ]
  )
}

module "ca_cert_secret" {
  source             = "registry.infrahouse.com/infrahouse/secret/aws"
  version            = "~> 1.0"
  environment        = var.environment
  service_name       = local.service_name
  secret_description = "CA certificate for cluster ${var.cluster_name}"
  secret_name_prefix = "${var.cluster_name}-ca-cert-"
  secret_value       = tls_self_signed_cert.ca_cert.cert_pem
  readers = concat(
    [
      module.elastic_cluster.instance_role_arn,
    ],
    var.bootstrap_mode ? [] : [
      module.elastic_cluster_data[0].instance_role_arn,
    ]
  )
}
