# Examples

Complete, runnable root modules live in the
[examples/](https://github.com/infrahouse/terraform-aws-elasticsearch/tree/main/examples)
directory of the repository:

| Example | What it shows |
|---------|---------------|
| [minimal][ex-minimal] | Smallest working cluster on defaults |
| [production][ex-production] | Sized node pools, restricted CIDRs, Prometheus, alarm routing, secret readers |

[ex-minimal]: https://github.com/infrahouse/terraform-aws-elasticsearch/tree/main/examples/minimal
[ex-production]: https://github.com/infrahouse/terraform-aws-elasticsearch/tree/main/examples/production

The snippets below cover configurations that come up often. All of them assume the
two-phase deployment described in [Getting Started](getting-started.md): apply once
with `bootstrap_mode = true`, then flip it to `false` and apply again.

## Minimal cluster

Three masters and three data nodes with defaults for everything else.

```hcl
module "elasticsearch" {
  source  = "registry.infrahouse.com/infrahouse/elasticsearch/aws"
  version = "5.1.1"

  providers = {
    aws     = aws
    aws.dns = aws.dns
  }

  cluster_name       = "elastic"
  environment        = "development"
  key_pair_name      = aws_key_pair.this.key_name
  subnet_ids         = module.service_network.subnet_private_ids
  zone_id            = data.aws_route53_zone.cluster.zone_id
  replication_region = "us-east-1"
  alarm_emails       = ["ops-team@example.com"]

  instance_type  = "t3.large"
  bootstrap_mode = true
}
```

## Sized production cluster

Masters hold cluster state, data nodes hold the indices - size them separately.

```hcl
module "elasticsearch" {
  # ... provider and required arguments as above ...

  cluster_master_count = 3
  cluster_data_count   = 6

  instance_type_master = "r6i.large"
  instance_type_data   = "r6i.2xlarge"

  master_nodes_root_volume_size = 30
  data_nodes_root_volume_size   = 500

  max_instance_lifetime_days = 90
  bootstrap_mode             = false
}
```

!!! warning "t3.medium is too small"
    The `instance_type` default exists for backwards compatibility. With
    `memory_lock = true` there is not enough RAM on a 4 GB instance for the JVM heap,
    the Lucene filesystem cache, and the OS - the OOM killer terminates Elasticsearch.
    Start at `t3.large`.

## Small development cluster

A single master and a single data node. Cheap, not highly available: losing the master
loses the cluster.

```hcl
module "elasticsearch" {
  # ... provider and required arguments ...

  cluster_master_count = 1
  cluster_data_count   = 1
  instance_type        = "t3.large"

  # Let terraform destroy remove the buckets even when they hold data.
  snapshot_force_destroy       = true
  alb_access_log_force_destroy = true
}
```

`cluster_master_count` must be odd, so 1 is the smallest valid master pool.

## Hosted zone in a different AWS account

The `aws.dns` provider alias exists so the DNS zone and the cluster can live in
different accounts. Point the alias at the account that owns the zone:

```hcl
provider "aws" {
  region = "us-west-2"
}

provider "aws" {
  alias  = "dns"
  region = "us-west-2"

  assume_role {
    role_arn = "arn:aws:iam::123456789012:role/dns-manager"
  }
}

data "aws_route53_zone" "cluster" {
  provider = aws.dns
  name     = "example.com."
}

module "elasticsearch" {
  # ...
  providers = {
    aws     = aws
    aws.dns = aws.dns
  }

  zone_id = data.aws_route53_zone.cluster.zone_id
}
```

## Restricting network access

Neither range should be `0.0.0.0/0` in production. The module rejects `0.0.0.0/0` for
`monitoring_cidr_block` outright.

```hcl
module "elasticsearch" {
  # ...

  # SSH from the jumphost subnet only.
  ssh_cidr_block = "10.1.10.0/24"

  # Prometheus scrapes node_exporter (9100) and elasticsearch_exporter (9114).
  monitoring_cidr_block = "10.1.0.0/16"
}
```

Client applications reach the cluster through the load balancers. Reference the
module's security group from a client security group when you need direct access:

```hcl
output "elasticsearch_sg" {
  value = module.elasticsearch.backend_security_group_id
}
```

## Granting access to the elastic password

The module already grants both instance profiles read access. Add the roles that your
people and pipelines use:

```hcl
data "aws_iam_roles" "sso_admin" {
  name_regex  = "AWSReservedSSO_AdministratorAccess.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

module "elasticsearch" {
  # ...
  secret_elastic_readers = [
    tolist(data.aws_iam_roles.sso_admin.arns)[0],
    aws_iam_role.deployer.arn,
  ]
}
```

Read the password with the returned secret id:

```bash
aws secretsmanager get-secret-value \
  --secret-id "$(terraform output -raw elastic_secret_id)" \
  --query SecretString --output text
```

## Alert routing beyond email

`alarm_emails` is required - every environment needs monitoring. Existing SNS topics
receive the same notifications, which is how PagerDuty, Slack, and OpsGenie get wired in:

```hcl
module "elasticsearch" {
  # ...
  alarm_emails = ["ops-team@example.com"]

  alarm_topic_arns = [
    aws_sns_topic.pagerduty.arn,
    aws_sns_topic.slack.arn,
  ]

  # Page on the first unhealthy host instead of the second.
  alarm_unhealthy_host_threshold = 0
  alarm_success_rate_threshold   = 99.5
  alarm_evaluation_periods       = 2
}
```

SNS sends a confirmation email to every address in `alarm_emails`. Until someone
clicks the link, that subscription delivers nothing.

## Tuning or disabling CloudWatch logging

Logging is on by default with 365-day retention, encrypted with a dedicated KMS key.
Retention below 365 days is rejected by validation.

```hcl
module "elasticsearch" {
  # ...
  enable_cloudwatch_logging           = true
  cloudwatch_log_retention_days       = 731
  cloudwatch_kms_rotation_period_days = 90
}
```

Turning it off removes the log group, the KMS key, and the logging IAM permissions.
Logs then stay on the instances only, and disappear when a node is replaced:

```hcl
module "elasticsearch" {
  # ...
  enable_cloudwatch_logging = false
}
```

## Extra packages, files, and APT repositories

Everything below is applied by cloud-init before Elasticsearch starts, on both node pools.

```hcl
module "elasticsearch" {
  # ...
  packages = ["jq", "htop"]

  extra_files = [
    {
      content     = file("${path.module}/files/sysctl-es.conf")
      path        = "/etc/sysctl.d/99-elasticsearch.conf"
      permissions = "0644"
    }
  ]

  extra_repos = {
    my_repo = {
      source = "deb https://apt.example.com/ubuntu jammy main"
      key    = file("${path.module}/files/apt-key.asc")
    }
  }
}
```

## Adding permissions to the instance profile

Pass a policy document JSON - it is merged into the instance profile policy:

```hcl
data "aws_iam_policy_document" "extra" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::my-bucket/*"]
  }
}

module "elasticsearch" {
  # ...
  extra_instance_profile_permissions = data.aws_iam_policy_document.extra.json
}
```

## Kibana on top of the cluster

The companion [terraform-aws-kibana](https://github.com/infrahouse/terraform-aws-kibana)
module deploys Kibana on ECS against this cluster, using the `kibana_system` password
the module created:

```hcl
module "kibana" {
  source  = "registry.infrahouse.com/infrahouse/kibana/aws"
  version = "2.0.0"

  providers = {
    aws     = aws
    aws.dns = aws.dns
  }

  elasticsearch_cluster_name = "elastic"
  elasticsearch_url          = module.elasticsearch.cluster_master_url
  kibana_system_password     = module.elasticsearch.kibana_system_password

  environment   = "production"
  zone_id       = data.aws_route53_zone.cluster.zone_id
  subnet_ids    = module.service_network.subnet_private_ids
  key_pair_name = aws_key_pair.this.key_name
  alarm_emails  = ["ops-team@example.com"]
}
```

See [Operations > Kibana](operations.md#kibana) for the full walkthrough.

## What's next

- [Configuration](configuration.md) - every variable explained
- [Architecture](architecture.md) - how the pieces fit together
- [Troubleshooting](troubleshooting.md) - when an apply or a node does not behave
