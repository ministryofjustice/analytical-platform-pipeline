##### Codepipeline #####
resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = "${var.name}-ap-codepipeline-bucket"
  acl    = "private"
  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name                  = "${var.name}-codepipeline-role"
  force_detach_policies = true
  assume_role_policy    = data.aws_iam_policy_document.assume_role.json
  tags                  = local.default_tags
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals = {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name   = "${var.name}-codepipeline-policy"
  role   = aws_iam_role.codepipeline_role.id
  policy = data.aws_iam_policy_document.code_pipeline.json
}

data "aws_iam_policy_document" "code_pipeline" {
  statement {
    effect  = "Allow"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.codepipeline_bucket.arn,
      "${aws_s3_bucket.codepipeline_bucket.arn}/*"
    ]
  }

  statement {
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild"
    ]
  }
}

resource "aws_codepipeline" "codepipeline" {
  name     = var.name
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        Owner  = var.pipeline_github_owner
        Repo   = var.pipeline_github_repo
        Branch = var.pipeline_github_branch
      }
    }
  }

  stage {
    name = "Plan"

    action {
      name            = "Build"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = aws_codebuild_project.build_project_tf_plan.name
      }
    }
  }

  stage {
    name = "Approve"

    action {
      name     = "Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
    }
  }

  stage {
    name = "Apply"

    action {
      name            = "Build"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = aws_codebuild_project.build_project_tf_apply.name
      }
    }
  }
}

#####  Codebuild #####
resource "aws_iam_role" "codebuild_role" {
  name                  = "${var.name}-codebuild-role"
  force_detach_policies = true

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF


  tags = local.default_tags
}

data "aws_iam_policy_document" "codebuild_policy" {
  source_json = var.codebuild_policy

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["*"]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObject",
    ]

    resources = [
      aws_s3_bucket.codepipeline_bucket.arn,
      "${aws_s3_bucket.codepipeline_bucket.arn}/*",
    ]
  }

  statement {
    actions = ["s3:*Object"]

    resources = [
      "${aws_s3_bucket.codepipeline_bucket.arn}/tfplan",
      "arn:aws:s3:::${var.tf_state_bucket}/*.tfstate",
    ]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.tf_state_bucket}"]
  }

  statement {
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = [
      "arn:aws:kms:${var.region}:${data.aws_caller_identity.current.account_id}:alias/aws/s3",
      var.tf_state_kms_key_arn,
    ]
  }

  statement {
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:DeleteItem",
    ]
    resources = [var.tf_lock_table_arn]
  }
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name   = "${var.name}-codebuild-policy"
  role   = aws_iam_role.codebuild_role.id
  policy = data.aws_iam_policy_document.codebuild_policy.json
}

resource "aws_codebuild_project" "build_project_tf_plan" {
  name          = "${var.name}-tf-plan"
  description   = "Build project to run infrastructure terraform plan"
  build_timeout = var.tf_plan_timeout
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                       = var.codebuild_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "TF_IN_AUTOMATION"
      value = "true"
    }

    environment_variable {
      name  = "PLAN_BUCKET"
      value = aws_s3_bucket.codepipeline_bucket.id
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "${var.buildspec_directory}/buildspec-plan.yml"
  }

  tags = local.default_tags
}

resource "aws_codebuild_project" "build_project_tf_apply" {
  name          = "${var.name}-tf-apply"
  description   = "Build project to apply infrastructure terraform plan"
  build_timeout = var.tf_apply_timeout
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                       = var.codebuild_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "TF_IN_AUTOMATION"
      value = "true"
    }

    environment_variable {
      name  = "PLAN_BUCKET"
      value = aws_s3_bucket.codepipeline_bucket.id
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "${var.buildspec_directory}/buildspec-apply.yml"
  }

  tags = local.default_tags
}

locals {
  default_tags = {
    business-unit = var.tags["business-unit"]
    application   = var.tags["application"]
    is-production = var.tags["is-production"]
    owner         = var.tags["owner"]
  }
}
