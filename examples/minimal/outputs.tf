output "cluster_url" {
  description = "HTTPS endpoint to access the cluster."
  value       = module.elasticsearch.cluster_url
}

output "elastic_secret_id" {
  description = "AWS secret that stores the password of the elastic superuser."
  value       = module.elasticsearch.elastic_secret_id
}

output "snapshots_bucket" {
  description = "S3 bucket where Elasticsearch snapshots are stored."
  value       = module.elasticsearch.snapshots_bucket
}
