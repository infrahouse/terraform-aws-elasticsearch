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

output "cloudwatch_log_group_name" {
  value = module.test.cloudwatch_log_group_name
}

output "master_asg_name" {
  value = module.test.master_asg_name
}

output "data_asg_name" {
  value = module.test.data_asg_name
}
