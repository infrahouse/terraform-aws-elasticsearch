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

# The module manages Route53 records via a dedicated provider alias so the DNS zone
# can live in a different AWS account than the cluster. Here both point to the same
# account, which is the common case.
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
  name = var.zone_name
}

module "elasticsearch" {
  source  = "registry.infrahouse.com/infrahouse/elasticsearch/aws"
  version = "5.2.0"

  providers = {
    aws     = aws
    aws.dns = aws.dns
  }

  cluster_name       = "elastic"
  environment        = var.environment
  key_pair_name      = var.key_pair_name
  subnet_ids         = var.subnet_ids
  zone_id            = data.aws_route53_zone.cluster.zone_id
  replication_region = var.replication_region
  alarm_emails       = var.alarm_emails

  # t3.medium (the module default) is too small: with memory_lock enabled there is
  # not enough RAM left for the OS and the Lucene filesystem cache.
  instance_type = "t3.large"

  # Apply once with true to form the cluster, then flip to false and apply again.
  bootstrap_mode = var.bootstrap_mode
}
