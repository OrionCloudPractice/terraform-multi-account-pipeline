// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

module "validation" {
  source                = "./modules/codebuild"
  codebuild_name        = lower("${var.pipeline_name}-validation")
  codebuild_role        = aws_iam_role.codebuild.arn
  environment_variables = merge(
    var.environment_variables,
    {
      SAST_REPORT_NAME = aws_codebuild_report_group.sast.name
    })
  build_timeout         = 5
  build_spec            = "validate.yml"
  log_group             = local.log_group
}

module "plan" {
  source         = "./modules/codebuild"
  codebuild_name = lower("${var.pipeline_name}-plan")
  codebuild_role = aws_iam_role.codebuild.arn
  environment_variables = var.environment_variables
  build_timeout = var.codebuild_timeout
  build_spec    = "plan.yml"
  log_group     = local.log_group
}

module "apply" {
  source         = "./modules/codebuild"
  codebuild_name = lower("${var.pipeline_name}-apply")
  codebuild_role = aws_iam_role.codebuild.arn
  environment_variables = var.environment_variables
  build_timeout = var.codebuild_timeout
  build_spec    = "apply.yml"
  log_group     = local.log_group
}

resource "aws_iam_role" "codebuild" {
  name               = "${var.pipeline_name}-codebuild"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}

data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values = [
        "arn:aws:codebuild:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:project/${var.pipeline_name}-*"
      ]
    }
  }
}

resource "aws_iam_role_policy_attachment" "codebuild" {
  role       = aws_iam_role.codebuild.name
  policy_arn = var.codebuild_policy == null ? aws_iam_policy.codebuild.arn : var.codebuild_policy
}

resource "aws_iam_policy" "codebuild" {
  name   = aws_iam_role.codebuild.name
  policy = data.aws_iam_policy_document.codebuild.json
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group}",
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group}:*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "codebuild:CreateReport",
      "codebuild:UpdateReport",
      "codebuild:BatchPutTestCases",
      "codebuild:CreateReportGroup"
    ]

    resources = [
      #all report groups
      "arn:aws:codebuild:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:report-group/*",
      #specific report group
      #aws_codebuild_report_group.sast.arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.this.arn}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole"
    ]

    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "dynamodb:*"
    ]

    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:*"
    ]

    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt"
    ]

    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "ssm:*"
    ]

    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "apigateway:*",
      "ec2:*",
      "ecs:*",
      "logs:*",
      "iam:*",
      "elasticloadbalancing:*",
      "cloudfront:*",
      "application-autoscaling:*",
      "ecr:*",
      "wafv2:*"
    ]

    resources = [
      "*"
    ]
  }
}

resource "aws_codebuild_report_group" "sast" {
  name           = "sast-report-${var.pipeline_name}"
  type           = "TEST"
  delete_reports = true

  export_config {
    type = "S3"

    s3_destination {
      bucket              = aws_s3_bucket.this.id
      encryption_disabled = false
      encryption_key      = try(var.kms_key, data.aws_kms_key.s3.arn)
      packaging           = "NONE"
      path                = "/sast"
    }
  }
}

