output "zone_id" {
  value = var.elastic_zone_id
}

output "cluster_url" {
  value = module.test.cluster_url
}

output "cluster_master_url" {
  value = module.test.cluster_master_url
}

output "cluster_data_url" {
  value = module.test.cluster_data_url
}
