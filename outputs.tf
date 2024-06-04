output "cluster_url" {
  description = "HTTPS endpoint to access the cluster"
  value       = "https://${var.cluster_name}.${data.aws_route53_zone.cluster.name}"
}

output "cluster_master_url" {
  description = "HTTPS endpoint to access the cluster masters"
  value       = "https://${var.cluster_name}-master.${data.aws_route53_zone.cluster.name}"
}

output "cluster_data_url" {
  description = "HTTPS endpoint to access the cluster data nodes"
  value       = "https://${var.cluster_name}-data.${data.aws_route53_zone.cluster.name}"
}

output "elastic_password" {
  description = "Password for Elasticsearch superuser elastic."
  sensitive   = true
  value       = module.secret_elastic.secret_value
}

output "elastic_secret_id" {
  description = "AWS secret that stores password for user elastic."
  value       = module.secret_elastic.secret_id
}

output "kibana_system_secret_id" {
  description = "AWS secret that stores password for user kibana_system"
  value       = module.secret_kibana_system.secret_id
}

output "kibana_system_password" {
  description = "A password of kibana_system user"
  sensitive   = true
  value       = module.secret_kibana_system.secret_value
}

output "snapshots_bucket" {
  description = "AWS S3 Bucket where Elasticsearch snapshots will be stored."
  value       = aws_s3_bucket.snapshots-bucket.bucket
}
