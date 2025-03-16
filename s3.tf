resource "random_string" "bucket_prefix" {
  length  = 12
  special = false
  numeric = false
  upper   = false
}

locals {
  bucket_prefix = var.snapshot_bucket_prefix == null ? random_string.bucket_prefix.result : var.snapshot_bucket_prefix
}
resource "aws_s3_bucket" "snapshots-bucket" {
  bucket_prefix = substr(local.bucket_prefix, 0, 37)
  tags = merge(
    {
      "cluster_name" : var.cluster_name
      module_version : local.module_version
    },
    local.default_module_tags
  )
  force_destroy = var.snapshot_force_destroy
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket                  = aws_s3_bucket.snapshots-bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
