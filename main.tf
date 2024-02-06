module "elastic_master_userdata" {
  source                   = "infrahouse/cloud-init/aws"
  version                  = "~> 1.7"
  environment              = var.environment
  role                     = "elastic_master"
  puppet_hiera_config_path = var.puppet_hiera_config_path
  puppet_module_path       = var.puppet_module_path

  packages = var.packages

  extra_files = var.extra_files
  extra_repos = var.extra_repos
}


module "elastic_cluster" {
  source  = "infrahouse/website-pod/aws"
  version = "~> 2.6"
  providers = {
    aws     = aws
    aws.dns = aws.dns
  }
  service_name          = var.cluster_name
  environment           = var.environment
  ami                   = data.aws_ami.ubuntu.image_id
  subnets               = var.subnet_ids
  backend_subnets       = var.subnet_ids
  zone_id               = var.zone_id
  internet_gateway_id   = var.internet_gateway_id
  key_pair_name         = var.key_pair_name
  dns_a_records         = [var.cluster_name]
  alb_name_prefix       = substr(var.cluster_name, 0, 6) ## "name_prefix" cannot be longer than 6 characters: "elastic"
  userdata              = module.elastic_master_userdata.userdata
  webserver_permissions = data.aws_iam_policy_document.elastic_permissions.json
  stickiness_enabled    = true
  asg_min_size          = 2
  asg_max_size          = 2
  instance_type         = var.instance_type
  target_group_port     = 9200
  alb_healthcheck_path = "/_nodes/stats"
  alb_healthcheck_port  = 9200
  health_check_grace_period = var.asg_health_check_grace_period
  extra_security_groups_backend = [
    aws_security_group.backend_extra.id
  ]

  asg_min_elb_capacity = 0
  instance_profile     = "${var.cluster_name}-master"
  tags = {
    Name : "${var.cluster_name} node"
    cluster : var.cluster_name
  }
}
