module "test" {
  source = "../../"
  providers = {
    aws     = aws
    aws.dns = aws
  }
  cluster_name           = "main-cluster"
  ubuntu_codename        = "noble"
  cluster_master_count   = 3
  cluster_data_count     = 2
  environment            = var.environment
  internet_gateway_id    = var.internet_gateway_id
  key_pair_name          = aws_key_pair.test.key_name
  subnet_ids             = var.lb_subnet_ids
  zone_id                = var.elastic_zone_id
  bootstrap_mode         = var.bootstrap_mode
  snapshot_bucket_prefix = "infrahouse-terraform-aws-elasticsearch"
  snapshot_force_destroy = true
  monitoring_cidr_block  = "0.0.0.0/0"
  secret_elastic_readers = [
    tolist(data.aws_iam_roles.sso-admin.arns)[0],
    "arn:aws:iam::990466748045:user/aleks"
  ]
}
