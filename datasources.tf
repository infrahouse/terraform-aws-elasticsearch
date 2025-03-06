data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_iam_role" "caller_role" {
  name = split("/", split(":", data.aws_caller_identity.current.arn)[5])[1]
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = [local.ami_name_pattern]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name = "state"
    values = [
      "available"
    ]
  }

  owners = ["099720109477"] # Canonical
}


data "aws_subnet" "selected" {
  id = var.subnet_ids[0]
}

data "aws_route53_zone" "cluster" {
  provider = aws.dns
  zone_id  = var.zone_id
}

data "aws_iam_policy_document" "secrets-permission-policy" {
  statement {
    principals {
      identifiers = [
        data.aws_iam_role.caller_role.arn,
      ]
      type = "AWS"
    }
    actions = [
      "secretsmanager:*"
    ]
    resources = [
      "*"
    ]
  }

  dynamic "statement" {
    for_each = var.secret_elastic_readers != null ? [{}] : []
    content {
      principals {
        identifiers = var.secret_elastic_readers
        type        = "AWS"
      }
      actions = [
        "secretsmanager:GetSecretValue",
      ]
      resources = [
        "*"
      ]
    }
  }

  statement {
    principals {
      identifiers = [
        "ec2.amazonaws.com",
      ]
      type = "Service"
    }
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      "*"
    ]
    condition {
      test = "ArnLike"
      values = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.master_profile_name}*",
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.data_profile_name}*"
      ]
      variable = "aws:SourceArn"
    }
  }
  statement {
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "secretsmanager:*"
    ]
    resources = [
      "*"
    ]
    condition {
      test = "StringNotLike"
      values = concat(
        [
          data.aws_iam_role.caller_role.arn,
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.master_profile_name}*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.data_profile_name}*"
        ],
        var.secret_elastic_readers == null ? [] : var.secret_elastic_readers,
      )
      variable = "aws:PrincipalArn"
    }
  }
}
