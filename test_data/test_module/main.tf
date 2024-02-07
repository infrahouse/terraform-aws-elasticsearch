module "test" {
  source = "../../"
  providers = {
    aws     = aws
    aws.dns = aws
  }
  cluster_name                  = "main-cluster"
  cluster_size                  = 3
  environment                   = var.environment
  internet_gateway_id           = module.service-network.internet_gateway_id
  key_pair_name                 = aws_key_pair.test.key_name
  subnet_ids                    = module.service-network.subnet_private_ids
  zone_id                       = data.aws_route53_zone.cicd.zone_id
  asg_health_check_grace_period = 3600 * 24
  bootstrap_mode                = false
}
