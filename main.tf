locals {
  master_profile_name     = "${var.cluster_name}-master-${random_string.profile-suffix.result}"
  data_profile_name       = "${var.cluster_name}-data-${random_string.profile-suffix.result}"
  tg_healthcheck_interval = 60
  alb_healthcheck_timeout = local.tg_healthcheck_interval / 2
}
module "elastic_master_userdata" {
  source                   = "registry.infrahouse.com/infrahouse/cloud-init/aws"
  version                  = "1.17.0"
  environment              = var.environment
  role                     = "elastic_master"
  puppet_hiera_config_path = var.puppet_hiera_config_path
  puppet_module_path       = var.puppet_module_path
  ubuntu_codename          = var.ubuntu_codename
  gzip_userdata            = true

  packages = var.packages

  extra_files = var.extra_files
  extra_repos = var.extra_repos

  custom_facts = merge(
    {
      "elasticsearch" : {
        "bootstrap_cluster" : var.bootstrap_mode
        "cluster_name" : var.cluster_name
        "elastic_secret" : aws_secretsmanager_secret.elastic.id
        "kibana_system_secret" : aws_secretsmanager_secret.kibana_system.id
        "snapshots_bucket" : aws_s3_bucket.snapshots-bucket.bucket
        "ca_key_secret" : module.ca_key_secret.secret_id
        "ca_cert_secret" : module.ca_cert_secret.secret_id
      }
      "letsencrypt" : {
        "domain" : data.aws_route53_zone.cluster.name
        "email" : "hostmaster@${data.aws_route53_zone.cluster.name}"
        "production" : true
      }
    },
    var.smtp_credentials_secret != null ? {
      postfix : {
        smtp_credentials : var.smtp_credentials_secret
      }
    } : {}
  )
  cancel_instance_refresh_on_error = true
}

module "elastic_data_userdata" {
  source                   = "registry.infrahouse.com/infrahouse/cloud-init/aws"
  version                  = "1.17.0"
  environment              = var.environment
  role                     = "elastic_data"
  puppet_hiera_config_path = var.puppet_hiera_config_path
  puppet_module_path       = var.puppet_module_path
  ubuntu_codename          = var.ubuntu_codename
  gzip_userdata            = true

  packages = var.packages

  extra_files = var.extra_files
  extra_repos = var.extra_repos

  custom_facts = merge(
    {
      "elasticsearch" : {
        "bootstrap_cluster" : false
        "cluster_name" : var.cluster_name
        "elastic_secret" : aws_secretsmanager_secret.elastic.id
        "kibana_system_secret" : aws_secretsmanager_secret.kibana_system.id
        "snapshots_bucket" : aws_s3_bucket.snapshots-bucket.bucket
        "ca_key_secret" : module.ca_key_secret.secret_id
        "ca_cert_secret" : module.ca_cert_secret.secret_id
      }
      "letsencrypt" : {
        "domain" : data.aws_route53_zone.cluster.name
        "email" : "hostmaster@${data.aws_route53_zone.cluster.name}"
        "production" : true
      }
    },
    var.smtp_credentials_secret != null ? {
      postfix : {
        smtp_credentials : var.smtp_credentials_secret
      }
    } : {}
  )
  cancel_instance_refresh_on_error = true
}

module "elastic_cluster" {
  source  = "registry.infrahouse.com/infrahouse/website-pod/aws"
  version = "5.1.1"
  providers = {
    aws     = aws
    aws.dns = aws.dns
  }
  service_name                 = local.service_name
  asg_name                     = var.cluster_name
  environment                  = var.environment
  ami                          = var.asg_ami != null ? var.asg_ami : data.aws_ami.ubuntu.image_id
  subnets                      = var.subnet_ids
  backend_subnets              = var.subnet_ids
  zone_id                      = var.zone_id
  internet_gateway_id          = var.internet_gateway_id
  key_pair_name                = var.key_pair_name
  ssh_cidr_block               = var.ssh_cidr_block
  dns_a_records                = [var.cluster_name, "${var.cluster_name}-master"]
  alb_name_prefix              = substr(var.cluster_name, 0, 6) ## "name_prefix" cannot be longer than 6 characters: "elastic"
  userdata                     = module.elastic_master_userdata.userdata
  instance_profile_permissions = data.aws_iam_policy_document.elastic_permissions.json
  stickiness_enabled           = true

  asg_min_size                                  = var.bootstrap_mode ? 1 : var.cluster_master_count
  asg_max_size                                  = var.bootstrap_mode ? 1 : var.cluster_master_count
  asg_lifecycle_hook_initial                    = var.asg_create_initial_lifecycle_hook ? module.update-dns.lifecycle_name_launching : null
  asg_lifecycle_hook_launching                  = module.update-dns.lifecycle_name_launching
  asg_lifecycle_hook_terminating                = module.update-dns.lifecycle_name_terminating
  asg_lifecycle_hook_launching_default_result   = "ABANDON"
  asg_lifecycle_hook_terminating_default_result = "CONTINUE"

  max_instance_lifetime_days            = var.max_instance_lifetime_days
  instance_type                         = var.instance_type_master != null ? var.instance_type_master : var.instance_type
  health_check_type                     = "EC2"
  target_group_port                     = 9200
  alb_healthcheck_path                  = "/_cluster/health?wait_for_status=yellow&timeout=${local.alb_healthcheck_timeout}s"
  alb_healthcheck_port                  = 9200
  alb_healthcheck_timeout               = local.alb_healthcheck_timeout
  alb_healthcheck_response_code_matcher = "200"
  alb_idle_timeout                      = 4000
  alb_healthcheck_interval              = local.tg_healthcheck_interval
  health_check_grace_period             = var.asg_health_check_grace_period
  wait_for_capacity_timeout             = "${var.asg_health_check_grace_period * 1.5}m"
  extra_security_groups_backend = [
    aws_security_group.backend_extra.id
  ]
  root_volume_size     = var.master_nodes_root_volume_size
  asg_min_elb_capacity = 1
  instance_role_name   = local.master_profile_name
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
  source  = "registry.infrahouse.com/infrahouse/website-pod/aws"
  version = "5.1.1"
  providers = {
    aws     = aws
    aws.dns = aws.dns
  }
  service_name                 = local.service_name
  asg_name                     = "${var.cluster_name}-data"
  environment                  = var.environment
  ami                          = var.asg_ami != null ? var.asg_ami : data.aws_ami.ubuntu.image_id
  subnets                      = var.subnet_ids
  backend_subnets              = var.subnet_ids
  zone_id                      = var.zone_id
  internet_gateway_id          = var.internet_gateway_id
  key_pair_name                = var.key_pair_name
  ssh_cidr_block               = var.ssh_cidr_block
  dns_a_records                = ["${var.cluster_name}-data"]
  alb_name_prefix              = substr(var.cluster_name, 0, 6) ## "name_prefix" cannot be longer than 6 characters: "elastic"
  userdata                     = module.elastic_data_userdata.userdata
  instance_profile_permissions = data.aws_iam_policy_document.elastic_permissions.json
  stickiness_enabled           = true

  asg_min_size                                  = var.cluster_data_count
  asg_max_size                                  = var.cluster_data_count
  alb_idle_timeout                              = 4000
  asg_lifecycle_hook_initial                    = var.asg_create_initial_lifecycle_hook ? module.update-dns-data.lifecycle_name_launching : null
  asg_lifecycle_hook_launching                  = module.update-dns-data.lifecycle_name_launching
  asg_lifecycle_hook_terminating                = module.update-dns-data.lifecycle_name_terminating
  asg_lifecycle_hook_launching_default_result   = "ABANDON"
  asg_lifecycle_hook_terminating_default_result = "CONTINUE"

  max_instance_lifetime_days            = var.max_instance_lifetime_days
  health_check_type                     = "EC2"
  instance_type                         = var.instance_type_data != null ? var.instance_type_data : var.instance_type
  target_group_port                     = 9200
  alb_healthcheck_path                  = "/_cluster/health?wait_for_status=yellow&timeout=${local.alb_healthcheck_timeout}s"
  alb_healthcheck_port                  = 9200
  alb_healthcheck_timeout               = local.alb_healthcheck_timeout
  alb_healthcheck_response_code_matcher = "200"
  alb_healthcheck_interval              = local.tg_healthcheck_interval
  health_check_grace_period             = var.asg_health_check_grace_period
  wait_for_capacity_timeout             = "${var.asg_health_check_grace_period * 1.5}s"
  extra_security_groups_backend = [
    aws_security_group.backend_extra.id
  ]
  root_volume_size     = var.data_nodes_root_volume_size
  asg_min_elb_capacity = 1
  instance_role_name   = local.data_profile_name
  tags = {
    Name : "${var.cluster_name} data node"
    cluster : var.cluster_name
    elastic_role : "data"
  }
}

resource "aws_autoscaling_lifecycle_hook" "terminating" {
  count                  = var.bootstrap_mode ? 0 : 1
  autoscaling_group_name = module.elastic_cluster_data[0].asg_name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
  name                   = "terminating"
  default_result         = "CONTINUE"
  heartbeat_timeout      = 3600
}
