module "update-dns" {
  source  = "infrahouse/update-dns/aws"
  version = "~> 0.5"
  # insert the 2 required variables here
  asg_name          = var.cluster_name
  route53_zone_id   = data.aws_route53_zone.cluster.zone_id
  route53_public_ip = false
}

module "update-dns-data" {
  source  = "infrahouse/update-dns/aws"
  version = "~> 0.5"
  # insert the 2 required variables here
  asg_name          = "${var.cluster_name}-data"
  route53_zone_id   = data.aws_route53_zone.cluster.zone_id
  route53_public_ip = false
}
