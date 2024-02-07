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
