resource "aws_secretsmanager_secret" "elastic" {
  name                    = "${var.cluster_name}-elastic-password"
  description             = "Password for user elastic in cluster ${var.cluster_name}"
  recovery_window_in_days = 0
  policy                  = data.aws_iam_policy_document.secrets-permission-policy.json
  tags = local.default_module_tags
}

resource "random_password" "elastic" {
  length = 21
}

resource "aws_secretsmanager_secret_version" "elastic" {
  secret_id     = aws_secretsmanager_secret.elastic.id
  secret_string = random_password.elastic.result
}


resource "aws_secretsmanager_secret" "kibana_system" {
  name                    = "${var.cluster_name}-kibana_system-password"
  description             = "Password for user kibana_system in cluster ${var.cluster_name}"
  recovery_window_in_days = 0
  policy                  = data.aws_iam_policy_document.secrets-permission-policy.json
  tags = local.default_module_tags
}

resource "random_password" "kibana_system" {
  length  = 21
  special = false
}

resource "aws_secretsmanager_secret_version" "kibana_system" {
  secret_id     = aws_secretsmanager_secret.kibana_system.id
  secret_string = random_password.kibana_system.result
}
