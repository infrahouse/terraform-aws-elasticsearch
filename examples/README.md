# Examples

Working root modules that deploy an Elasticsearch cluster with
[terraform-aws-elasticsearch](../README.md). Each directory is self-contained:
copy `terraform.tfvars.example` to `terraform.tfvars`, fill in your VPC, hosted
zone, and key pair, then `terraform init && terraform apply`.

| Example | What it shows |
|---------|---------------|
| [minimal](minimal) | Smallest working cluster - defaults, HTTPS endpoints, snapshots, logging |
| [production](production) | Sized node pools, restricted CIDRs, Prometheus, alarm routing, secret readers |

## Every example is a two-phase deployment

A new cluster is created with `bootstrap_mode = true`, which deploys a single master
node that forms the cluster and generates the credentials. After that apply succeeds,
set `bootstrap_mode = false` and apply again to scale out to the full cluster. Nodes
join through ASG lifecycle hooks, so the second apply waits for the instance refreshes.

See [Getting Started](https://infrahouse.github.io/terraform-aws-elasticsearch/getting-started/)
for a full walkthrough and [Configuration](https://infrahouse.github.io/terraform-aws-elasticsearch/configuration/)
for the variable reference.

## Prerequisites shared by all examples

- Terraform >= 1.5 and the AWS provider `~> 6.0`.
- A VPC with at least two private subnets in different availability zones. The
  [service-network](https://registry.terraform.io/modules/infrahouse/service-network/aws/latest)
  module creates a suitable one.
- A Route53 hosted zone for the cluster endpoints.
- An EC2 key pair for SSH access.
- At least one email address for `alarm_emails`. The module requires it - development
  clusters need monitoring too.

## Cost warning

These examples create real infrastructure: EC2 instances, two Application Load
Balancers, S3 buckets with cross-region replication, a KMS key, and CloudWatch logs.
Run `terraform destroy` when you are done experimenting. The snapshot and access log
buckets survive a destroy unless `snapshot_force_destroy` and
`alb_access_log_force_destroy` are set to `true`.
