output "zone_id" {
  value = data.aws_route53_zone.cicd.zone_id
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

output "jumphost_asg_name" {
  value = module.jumphost.jumphost_asg_name
}
