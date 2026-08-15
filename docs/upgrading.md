# Upgrading

## 5.1.x to 5.2

A dependency refresh. No variables were added, removed, or renamed, but two of the
updated modules change behavior on apply.

### What to expect on the first apply

- **All instances are replaced.** website-pod 6.2.0 encrypts the ASG root EBS volume
  unconditionally, so the launch template changes and both ASGs run an instance
  refresh. Nodes roll one at a time through the usual lifecycle hooks: each new node
  joins before the old one is decommissioned, and shards are drained on the way out.
  Expect the apply to take as long as a normal node roll, and run it in a maintenance
  window if the cluster is at capacity. Cluster health should never leave `yellow`.
- **A tag update on two secrets.** The `elastic` and `kibana_system` secrets now carry
  `service = <cluster_name>` instead of `service = unknown`, because `service_name` is
  passed to the secret module explicitly. `secret/aws` deprecates the old default in
  its v2.0.

### AWS provider floor raised to 6.33.0

The module now requires `>= 6.33.0, < 7.0.0` instead of `~> 6.0`, following
website-pod 6.4.0. If your root module pins the AWS provider below 6.33.0,
`terraform init` fails until you raise it.

### New constraint on `environment`

`environment` must now contain only lowercase letters, numbers, and underscores.
A value with a hyphen, for example `prod-us`, is rejected at plan time. The rule comes
from `secret/aws` 1.3.0, and this module validates the same pattern on its own
`environment` variable so the error points at your module call rather than at a
resource inside the module tree.

Rename the environment to `prod_us` before upgrading. The value is also the Puppet
environment name, so it has to match on the Puppet side as well.

### Migration steps

1. Raise the AWS provider constraint in your root module if it is pinned below 6.33.0.
2. Run `terraform init -upgrade`.
3. Run `terraform plan` and confirm the changes are limited to launch templates,
   instance refreshes, and secret tags - no bucket, secret, or load balancer
   replacement.
4. Apply, then watch the refresh:

    ```bash
    aws autoscaling describe-instance-refreshes --auto-scaling-group-name <cluster_name>
    ```

5. Confirm cluster health is `green` before draining the maintenance window:

    ```bash
    curl -u "elastic:${ELASTIC_PASSWORD}" "https://<cluster>/_cluster/health?pretty"
    ```

### What changed internally

- **website-pod** 6.0.1 to 6.4.0 - root EBS volume encryption, optional ASG warm pool,
  `cpu_options` passthrough, GPU ECS autoscaling support, and an AWS provider floor of
  6.33.0. New inputs are all optional and unused by this module.
- **secret/aws** 1.1.1 to 1.3.0 - optional customer-managed CMK for cross-account
  access (opt-in via `create_cross_account_cmk`, left off), a precondition that exactly
  one of `secret_name` / `secret_name_prefix` is set, and the `environment` validation
  above.
- **s3-bucket/aws** 0.6.0 to 0.9.0 - optional S3 Object Lock and SSE-KMS with a
  customer-managed key. Both default to off, so the snapshots bucket keeps SSE-S3.
- **infrahouse-core** (test dependency) `~= 0.17` to `~= 1.1`. The `ASG`, `EC2Instance`,
  and `setup_logging` APIs the tests use are unchanged.

## 4.x to 5.0

### Breaking changes

- **New required variable `replication_region`** — all consumers must add this
  variable. There is no default; you must specify the AWS region for
  cross-region replication of S3 buckets (ALB access logs and snapshots).
- **AWS provider ~> 6.0 required** — provider v5 is no longer supported.
  Website-pod 6.0.1 (used internally) requires AWS provider v6.

### Migration steps

1. Add `replication_region` to your module call:

    ```hcl
    module "elasticsearch" {
      source  = "registry.infrahouse.com/infrahouse/elasticsearch/aws"
      version = "5.0.0"

      # ... existing variables ...
      replication_region = "us-east-1"
    }
    ```

2. Run `terraform init -upgrade` to fetch new module versions.

3. Run `terraform plan` and verify:
    - The snapshots bucket shows as **moved**, not destroyed/recreated.
      You should see lines like:
      ```
      # aws_s3_bucket.snapshots-bucket has moved to
      #   module.snapshots_bucket.aws_s3_bucket.this
      ```
    - New resources are created for CRR (replica bucket, replication
      configuration, IAM role).
    - The `internet_gateway_id` input to website-pod is removed (no action
      needed on your part).

4. Apply.

5. Run S3 batch replication to backfill existing objects in the snapshots
   bucket to the replica region.

### What changed internally

- **website-pod** bumped from 5.13.0 to 6.0.1 — ALB access log buckets now
  get cross-region replication via the `replication_region` passthrough.
- **Snapshots bucket** migrated from raw `aws_s3_bucket` resources to the
  `infrahouse/s3-bucket/aws` module (0.6.0). State is moved via `moved`
  blocks — no bucket recreation. The module handles SSL-only policy,
  public access blocking, and CRR configuration.
- **update-dns** bumped from 1.2.1 to 1.4.0 (Vanta S3 compliance in
  lambda-monitored).
- **`internet_gateway_id`** removed from website-pod (no longer needed in v6).
  The corresponding data sources (`aws_internet_gateway`, `aws_vpc`) are
  removed from this module.
