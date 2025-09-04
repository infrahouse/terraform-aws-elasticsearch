output "cluster_url" {
  description = "HTTPS endpoint to access the cluster"
  value       = "https://${var.cluster_name}.${data.aws_route53_zone.cluster.name}"
}

output "cluster_master_url" {
  description = "HTTPS endpoint to access the cluster masters"
  value       = "https://${var.cluster_name}-master.${data.aws_route53_zone.cluster.name}"
}

output "cluster_master_load_balancer_arn" {
  description = "ARN of the load balancer for the cluster masters"
  value       = module.elastic_cluster.load_balancer_arn
}

output "cluster_master_target_group_arn" {
  description = "ARN of the target group for the cluster master nodes"
  value       = module.elastic_cluster.target_group_arn
}

output "cluster_master_ssl_listener_arn" {
  description = "ARN of cluster masters ssl listener of balancer"
  value       = module.elastic_cluster.ssl_listener_arn
}

output "cluster_data_url" {
  description = "HTTPS endpoint to access the cluster data nodes"
  value       = "https://${var.cluster_name}-data.${data.aws_route53_zone.cluster.name}"
}

output "cluster_data_load_balancer_arn" {
  description = "ARN of the load balancer for the cluster data nodes"
  value       = var.bootstrap_mode ? null : module.elastic_cluster_data[0].load_balancer_arn
}

output "cluster_data_target_group_arn" {
  description = "ARN of the target group for the cluster data nodes"
  value       = var.bootstrap_mode ? null : module.elastic_cluster_data[0].target_group_arn
}

output "cluster_data_ssl_listener_arn" {
  description = "ARN of cluster data ssl listener of balancer"
  value       = var.bootstrap_mode ? null : module.elastic_cluster_data[0].ssl_listener_arn
}

output "elastic_password" {
  description = "Password for Elasticsearch superuser elastic."
  sensitive   = true
  value       = module.elastic-password.secret_value
}

output "elastic_secret_id" {
  description = "AWS secret that stores password for user elastic."
  value       = module.elastic-password.secret_id
}

output "idle_timeout_data" {
  description = "The amount of time a client or target connection can be idle before the load balancer (that fronts data nodes) closes it."
  value       = var.idle_timeout_data
}

output "idle_timeout_master" {
  description = "The amount of time a client or target connection can be idle before the load balancer (that fronts master nodes) closes it."
  value       = var.idle_timeout_master
}

output "kibana_system_secret_id" {
  description = "AWS secret that stores password for user kibana_system"
  value       = module.kibana_system-password.secret_id
}

output "kibana_system_password" {
  description = "A password of kibana_system user"
  sensitive   = true
  value       = module.kibana_system-password.secret_value
}

output "snapshots_bucket" {
  description = "AWS S3 Bucket where Elasticsearch snapshots will be stored."
  value       = aws_s3_bucket.snapshots-bucket.bucket
}

output "master_instance_role_arn" {
  description = "Master node EC2 instance profile will have this role ARN"
  value       = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.master_profile_name}"
}

output "data_instance_role_arn" {
  description = "Data node EC2 instance profile will have this role ARN"
  value       = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.data_profile_name}"
}
