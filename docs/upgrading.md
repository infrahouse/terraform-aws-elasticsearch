# Upgrading

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
