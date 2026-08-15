terraform {
  required_version = "~> 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      created_by = "infrahouse/terraform-aws-elasticsearch"
    }
  }
}

# The DNS zone may live in another AWS account. Point this alias at the account that
# owns the hosted zone - assume_role can be added here when it is a separate account.
provider "aws" {
  alias  = "dns"
  region = var.region

  default_tags {
    tags = {
      created_by = "infrahouse/terraform-aws-elasticsearch"
    }
  }
}

data "aws_route53_zone" "cluster" {
  provider = aws.dns
  name     = var.zone_name
}

module "elasticsearch" {
  source  = "registry.infrahouse.com/infrahouse/elasticsearch/aws"
  version = "5.1.1"

  providers = {
    aws     = aws
    aws.dns = aws.dns
  }

  cluster_name       = var.cluster_name
  environment        = var.environment
  key_pair_name      = var.key_pair_name
  subnet_ids         = var.subnet_ids
  zone_id            = data.aws_route53_zone.cluster.zone_id
  replication_region = var.replication_region
  bootstrap_mode     = var.bootstrap_mode

  # Master nodes only hold cluster state, so they need far less memory than data nodes.
  cluster_master_count = 3
  cluster_data_count   = 6
  instance_type_master = "r6i.large"
  instance_type_data   = "r6i.2xlarge"

  # Data nodes hold the indices - size the root volume for the working set plus overhead.
  master_nodes_root_volume_size = 30
  data_nodes_root_volume_size   = 500

  # Recycle instances quarterly so they pick up fresh AMIs and patches.
  max_instance_lifetime_days = 90

  # Network access. Neither range should be 0.0.0.0/0 in production.
  ssh_cidr_block        = var.admin_cidr_block
  monitoring_cidr_block = var.monitoring_cidr_block

  # Long-running search and indexing requests need a generous ALB idle timeout.
  idle_timeout_master = 4000
  idle_timeout_data   = 4000

  # Logs are encrypted with a dedicated KMS key that rotates every 90 days.
  enable_cloudwatch_logging     = true
  cloudwatch_log_retention_days = 365

  # Alerting: emails plus any existing topics wired into PagerDuty, Slack, OpsGenie.
  alarm_emails                   = var.alarm_emails
  alarm_topic_arns               = var.alarm_topic_arns
  alarm_unhealthy_host_threshold = 0
  alarm_success_rate_threshold   = 99.5
  alarm_evaluation_periods       = 2

  # Roles allowed to read the elastic superuser password, in addition to the cluster
  # instance profiles that the module grants automatically.
  secret_elastic_readers = var.secret_elastic_readers

  # A stable prefix keeps the snapshot bucket name predictable across rebuilds.
  snapshot_bucket_prefix = "${var.cluster_name}-snapshots"
}
