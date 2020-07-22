variable "name" {
}

variable "pipeline_github_owner" {
}

variable "pipeline_github_repo" {
}

variable "pipeline_github_branch" {
}

variable "codebuild_policy" {
  description = "aws_iam_policy_document specifying the required permissions for codebuild to run Terraform"
}

data "aws_caller_identity" "current" {
}

variable "region" {
  default = "eu-west-1"
}

variable "tf_plan_timeout" {
  default = "5"
}

variable "tf_apply_timeout" {
  default = "20"
}

variable "codebuild_compute_type" {
  default = "BUILD_GENERAL1_SMALL"
}

variable "codebuild_image" {
  default = "aws/codebuild/standard:1.0"
}

variable "buildspec_directory" {
  default = "pipeline"
}

variable "tf_state_bucket" {
  default = "tf-state-analytical-platform-landing"
}

variable "tf_state_kms_key_arn" {
  default = "arn:aws:kms:eu-west-1:335823981503:key/925a5b6c-7df1-49a0-a3cc-471e8524637d"
}

variable "tf_lock_table_arn" {
  default = "arn:aws:dynamodb:*:*:table/tf-state-lock"
}

variable "tags" {
  type = map(string)

  default = {
    business-unit = "Platforms"
    application   = "analytical-platform"
    is-production = true
    owner         = "analytical-platform:analytics-platform-tech@digital.justice.gov.uk"
  }
}

