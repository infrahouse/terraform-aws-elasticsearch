# Minimal Elasticsearch cluster

The smallest configuration that produces a working cluster: 3 master nodes,
3 data nodes, HTTPS endpoints, snapshots, and CloudWatch logging on defaults.

## Prerequisites

- A VPC with at least two private subnets in different availability zones.
  The [service-network](https://registry.terraform.io/modules/infrahouse/service-network/aws/latest)
  module creates them.
- A Route53 hosted zone for the cluster endpoints.
- An EC2 key pair for SSH access to the instances.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your zone, subnets, key pair, and alarm emails

terraform init
terraform apply            # phase 1: bootstrap_mode = true
```

The first apply creates a single master node that forms the cluster and generates
the credentials. When it completes, flip the flag and apply again:

```bash
sed -i.bak 's/bootstrap_mode = true/bootstrap_mode = false/' terraform.tfvars
terraform apply            # phase 2: scale to 3 masters + 3 data nodes
```

Every node joins the cluster through an ASG lifecycle hook, so the second apply
waits for the instance refreshes to finish. See
[Getting Started](https://infrahouse.github.io/terraform-aws-elasticsearch/getting-started/)
for what happens during each phase.

## Verify

```bash
ELASTIC_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id "$(terraform output -raw elastic_secret_id)" \
  --query SecretString --output text)

curl -u "elastic:${ELASTIC_PASSWORD}" "$(terraform output -raw cluster_url)/_cluster/health?pretty"
```

## Notes

- `instance_type` is set to `t3.large`. The module default (`t3.medium`) exists for
  backwards compatibility and is too small for real workloads - the OOM killer
  terminates Elasticsearch when `memory_lock` is enabled.
- `alarm_emails` is required: every environment needs monitoring. Confirm the SNS
  subscription emails after the first apply.
- Destroying the cluster leaves the snapshot and access log buckets in place unless
  `snapshot_force_destroy` and `alb_access_log_force_destroy` are set to `true`.
