resource "random_string" "bucket_prefix" {
  length  = 12
  special = false
  numeric = false
  upper   = false
}

locals {
  bucket_prefix = var.snapshot_bucket_prefix == null ? random_string.bucket_prefix.result : var.snapshot_bucket_prefix
}

module "snapshots_bucket" {
  source             = "registry.infrahouse.com/infrahouse/s3-bucket/aws"
  version            = "0.9.0"
  bucket_prefix      = substr(local.bucket_prefix, 0, 29)
  force_destroy      = var.snapshot_force_destroy
  replication_region = var.replication_region
  tags = merge(
    {
      "cluster_name" : var.cluster_name
      module_version : local.module_version
    },
    local.default_module_tags
  )
}

moved {
  from = aws_s3_bucket.snapshots-bucket
  to   = module.snapshots_bucket.aws_s3_bucket.this
}

moved {
  from = aws_s3_bucket_public_access_block.public_access
  to   = module.snapshots_bucket.aws_s3_bucket_public_access_block.public_access
}

moved {
  from = aws_s3_bucket_policy.snapshots-bucket
  to   = module.snapshots_bucket.aws_s3_bucket_policy.this
}
