data "aws_iam_policy_document" "elastic_permissions" {
  # https://www.elastic.co/guide/en/elasticsearch/plugins/current/discovery-ec2-usage.html#discovery-ec2-permissions
  source_policy_documents = concat(
    var.extra_instance_profile_permissions != null ? [var.extra_instance_profile_permissions] : [],
    var.enable_cloudwatch_logging ? [data.aws_iam_policy_document.cloudwatch_logs_permissions[0].json] : []
  )
  statement {
    actions = [
      "ec2:DescribeInstances",
      "autoscaling:DescribeAutoScalingInstances",

    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "autoscaling:CompleteLifecycleAction",
      "autoscaling:CancelInstanceRefresh",
      "autoscaling:SetInstanceHealth",
      "autoscaling:RecordLifecycleActionHeartbeat",

    ]
    resources = [
      "arn:aws:autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${var.cluster_name}-data",
      "arn:aws:autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${var.cluster_name}",
    ]
  }
  statement {
    actions = [
      "route53:GetChange",
      "route53:ListHostedZones",
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "route53:ChangeResourceRecordSets",
    ]
    resources = [
      data.aws_route53_zone.cluster.arn
    ]
  }
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      module.elastic-password.secret_arn,
      module.kibana_system-password.secret_arn,
      module.ca_cert_secret.secret_arn,
      module.ca_key_secret.secret_arn,
    ]
  }
  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
      "s3:ListBucketVersions"
    ]
    resources = [
      aws_s3_bucket.snapshots-bucket.arn
    ]
  }
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
    resources = [
      "${aws_s3_bucket.snapshots-bucket.arn}/*"
    ]
  }
}
