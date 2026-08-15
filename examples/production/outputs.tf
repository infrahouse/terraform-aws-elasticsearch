output "cluster_url" {
  description = "HTTPS endpoint to access the cluster."
  value       = module.elasticsearch.cluster_url
}

output "cluster_data_url" {
  description = "HTTPS endpoint that fronts the data nodes."
  value       = module.elasticsearch.cluster_data_url
}

output "elastic_secret_id" {
  description = "AWS secret that stores the password of the elastic superuser."
  value       = module.elasticsearch.elastic_secret_id
}

output "kibana_system_secret_id" {
  description = "AWS secret that stores the password of the kibana_system user."
  value       = module.elasticsearch.kibana_system_secret_id
}

output "snapshots_bucket" {
  description = "S3 bucket where Elasticsearch snapshots are stored."
  value       = module.elasticsearch.snapshots_bucket
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group with the Elasticsearch logs."
  value       = module.elasticsearch.cloudwatch_log_group_name
}

output "alarm_sns_topic_arn" {
  description = "SNS topic that receives the CloudWatch alarm notifications of the master nodes."
  value       = module.elasticsearch.alarm_sns_topic_arn
}

output "backend_security_group_id" {
  description = "Security group of the Elasticsearch instances. Reference it to allow client access."
  value       = module.elasticsearch.backend_security_group_id
}
