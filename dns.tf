module "update-dns" {
  source            = "registry.infrahouse.com/infrahouse/update-dns/aws"
  version           = "1.2.1"
  asg_name          = var.cluster_name
  route53_zone_id   = data.aws_route53_zone.cluster.zone_id
  route53_public_ip = false

  # Alert Configuration (new in v4.0.0)
  alarm_emails   = var.alarm_emails
  alert_strategy = "immediate" # DNS failures are critical - always alert immediately
}

module "update-dns-data" {
  source            = "registry.infrahouse.com/infrahouse/update-dns/aws"
  version           = "1.2.1"
  asg_name          = "${var.cluster_name}-data"
  route53_zone_id   = data.aws_route53_zone.cluster.zone_id
  route53_public_ip = false

  # Alert Configuration (new in v4.0.0)
  alarm_emails   = var.alarm_emails
  alert_strategy = "immediate" # DNS failures are critical - always alert immediately
}
