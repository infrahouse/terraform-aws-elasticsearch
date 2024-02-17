resource "random_string" "subdomain" {
  length  = 6
  numeric = false
  special = false
  upper   = false
}

resource "aws_route53_zone" "subzone" {
  name = "${random_string.subdomain.result}.${data.aws_route53_zone.parent.name}"
}

resource "aws_route53_record" "subzone-ns" {
  name    = aws_route53_zone.subzone.name
  type    = "NS"
  zone_id = data.aws_route53_zone.parent.zone_id
  ttl     = 172800
  records = aws_route53_zone.subzone.name_servers
}
