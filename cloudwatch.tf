resource "aws_kms_key" "cloudwatch_logs" {
  count                   = var.enable_cloudwatch_logging ? 1 : 0
  description             = "KMS key for encrypting CloudWatch logs for Elasticsearch cluster ${var.cluster_name}"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name        = "${var.cluster_name}-cloudwatch-logs"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "cloudwatch_logs" {
  count         = var.enable_cloudwatch_logging ? 1 : 0
  name          = "alias/${var.cluster_name}-cloudwatch-logs"
  target_key_id = aws_kms_key.cloudwatch_logs[0].key_id
}

data "aws_iam_policy_document" "cloudwatch_logs_key_policy" {
  count = var.enable_cloudwatch_logging ? 1 : 0

  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "Allow CloudWatch Logs to use the key"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_name}"]
    }
  }
}

resource "aws_kms_key_policy" "cloudwatch_logs" {
  count  = var.enable_cloudwatch_logging ? 1 : 0
  key_id = aws_kms_key.cloudwatch_logs[0].id
  policy = data.aws_iam_policy_document.cloudwatch_logs_key_policy[0].json
}

resource "aws_cloudwatch_log_group" "elasticsearch" {
  count             = var.enable_cloudwatch_logging ? 1 : 0
  name              = local.log_group_name
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.cloudwatch_logs[0].arn

  tags = {
    Name        = "${var.cluster_name}-elasticsearch"
    Environment = var.environment
    Cluster     = var.cluster_name
  }
}

data "aws_iam_policy_document" "cloudwatch_logs_permissions" {
  count = var.enable_cloudwatch_logging ? 1 : 0

  statement {
    sid = "CloudWatchLogsAccess"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = [
      aws_cloudwatch_log_group.elasticsearch[0].arn,
      "${aws_cloudwatch_log_group.elasticsearch[0].arn}:*"
    ]
  }

  statement {
    sid = "KMSDecryptForLogs"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = [
      aws_kms_key.cloudwatch_logs[0].arn
    ]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}
