data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-${var.ubuntu_codename}-*"]
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


data "aws_iam_policy_document" "elastic_permissions" {
  # https://www.elastic.co/guide/en/elasticsearch/plugins/current/discovery-ec2-usage.html#discovery-ec2-permissions
  statement {
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

data "aws_subnet" "selected" {
  id = var.subnet_ids[0]
}
