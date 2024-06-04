module "elastic_master_userdata" {
  source                   = "infrahouse/cloud-init/aws"
  version                  = "= 1.11.1"
  environment              = var.environment
  role                     = "elastic_master"
  puppet_hiera_config_path = var.puppet_hiera_config_path
  puppet_module_path       = var.puppet_module_path

  packages = var.packages

  extra_files = var.extra_files
  extra_repos = var.extra_repos

  custom_facts = {
    "elasticsearch" : {
      "bootstrap_cluster" : var.bootstrap_mode
      "cluster_name" : var.cluster_name
      "elastic_secret" : aws_secretsmanager_secret.elastic.id
      "kibana_system_secret" : aws_secretsmanager_secret.kibana_system.id
      "snapshots_bucket" : aws_s3_bucket.snapshots-bucket.bucket
    }
    "letsencrypt" : {
      "domain" : data.aws_route53_zone.cluster.name
      "email" : "hostmaster@${data.aws_route53_zone.cluster.name}"
      "production" : true
    }
  }
}

module "elastic_data_userdata" {
  source                   = "infrahouse/cloud-init/aws"
  version                  = "= 1.11.1"
  environment              = var.environment
  role                     = "elastic_data"
  puppet_hiera_config_path = var.puppet_hiera_config_path
  puppet_module_path       = var.puppet_module_path

  packages = var.packages

  extra_files = var.extra_files
  extra_repos = var.extra_repos

  custom_facts = {
    "elasticsearch" : {
      "bootstrap_cluster" : false
      "cluster_name" : var.cluster_name
      "elastic_secret" : aws_secretsmanager_secret.elastic.id
      "kibana_system_secret" : aws_secretsmanager_secret.kibana_system.id
      "snapshots_bucket" : aws_s3_bucket.snapshots-bucket.bucket
    }
    "letsencrypt" : {
      "domain" : data.aws_route53_zone.cluster.name
      "email" : "hostmaster@${data.aws_route53_zone.cluster.name}"
      "production" : true
    }
  }
}

module "elastic_cluster" {
  source  = "infrahouse/website-pod/aws"
  version = "= 2.8.3"
  providers = {
    aws     = aws
    aws.dns = aws.dns
  }
  service_name                          = var.cluster_name
  asg_name                              = var.cluster_name
  environment                           = var.environment
  ami                                   = var.asg_ami != null ? var.asg_ami : data.aws_ami.ubuntu.image_id
  subnets                               = var.subnet_ids
  backend_subnets                       = var.subnet_ids
  zone_id                               = var.zone_id
  alb_internal                          = true
  internet_gateway_id                   = var.internet_gateway_id
  key_pair_name                         = var.key_pair_name
  dns_a_records                         = [var.cluster_name, "${var.cluster_name}-master"]
  alb_name_prefix                       = substr(var.cluster_name, 0, 6) ## "name_prefix" cannot be longer than 6 characters: "elastic"
  userdata                              = module.elastic_master_userdata.userdata
  webserver_permissions                 = data.aws_iam_policy_document.elastic_permissions.json
  stickiness_enabled                    = true
  asg_min_size                          = var.bootstrap_mode ? 1 : var.cluster_master_count
  asg_max_size                          = var.bootstrap_mode ? 1 : var.cluster_master_count
  max_instance_lifetime_days            = 0
  instance_type                         = var.instance_type
  target_group_port                     = 9200
  alb_healthcheck_path                  = "/"
  alb_healthcheck_port                  = 9200
  alb_healthcheck_response_code_matcher = "200"
  alb_healthcheck_interval              = 300
  health_check_grace_period             = var.asg_health_check_grace_period
  wait_for_capacity_timeout             = "${var.asg_health_check_grace_period * 1.5}m"
  extra_security_groups_backend = [
    aws_security_group.backend_extra.id
  ]

  asg_min_elb_capacity = 1
  instance_profile     = "${var.cluster_name}-master-${random_string.profile-suffix.result}"
  tags = {
    Name : "${var.cluster_name} master node"
    cluster : var.cluster_name
    elastic_role : "master"
  }
}

resource "random_string" "profile-suffix" {
  length  = 6
  special = false
}

module "elastic_cluster_data" {
  # Deploy only if not in the bootstrap mode
  count   = var.bootstrap_mode ? 0 : 1
  source  = "infrahouse/website-pod/aws"
  version = "= 2.8.3"
  providers = {
    aws     = aws
    aws.dns = aws.dns
  }
  service_name                          = var.cluster_name
  asg_name                              = "${var.cluster_name}-data"
  environment                           = var.environment
  ami                                   = var.asg_ami != null ? var.asg_ami : data.aws_ami.ubuntu.image_id
  subnets                               = var.subnet_ids
  backend_subnets                       = var.subnet_ids
  zone_id                               = var.zone_id
  alb_internal                          = true
  internet_gateway_id                   = var.internet_gateway_id
  key_pair_name                         = var.key_pair_name
  dns_a_records                         = ["${var.cluster_name}-data"]
  alb_name_prefix                       = substr(var.cluster_name, 0, 6) ## "name_prefix" cannot be longer than 6 characters: "elastic"
  userdata                              = module.elastic_data_userdata.userdata
  webserver_permissions                 = data.aws_iam_policy_document.elastic_permissions.json
  stickiness_enabled                    = true
  asg_min_size                          = var.cluster_data_count
  asg_max_size                          = var.cluster_data_count
  max_instance_lifetime_days            = 0
  instance_type                         = var.instance_type
  target_group_port                     = 9200
  alb_healthcheck_path                  = "/"
  alb_healthcheck_port                  = 9200
  alb_healthcheck_response_code_matcher = "200"
  alb_healthcheck_interval              = 300
  health_check_grace_period             = var.asg_health_check_grace_period
  wait_for_capacity_timeout             = "${var.asg_health_check_grace_period * 1.5}s"
  extra_security_groups_backend = [
    aws_security_group.backend_extra.id
  ]

  asg_min_elb_capacity = 1
  instance_profile     = "${var.cluster_name}-data-${random_string.profile-suffix.result}"
  tags = {
    Name : "${var.cluster_name} data node"
    cluster : var.cluster_name
    elastic_role : "data"
  }
}
