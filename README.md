# Analytical Platform Pipeline
AWS Pipeline Terraform Module

Creates an AWS Codepipeline and required resources to apply terraform within a pipeline

![Image](iam-pipeline.png?raw=true)

## Prerequisites

AWS Codepipeline requires a github personal access token. You can create one in <https://github.com/settings/tokens>. This needs to be set as an environment variable called GITHUB_TOKEN.

```bash
export GITHUB_TOKEN=<yourgithubpersonalaccesstokenhere>
```

Two buildspec.yaml files need to be defined in the source code repository. One is used for the terraform plan stage and the other for the terraform apply stage. These should be named `buildspec-plan.yml` and `buildspec-apply.yml`. Examples of these are shown below

## Usage

The example below specifies the minimum parameters the module requires to create a pipeline. Pass in a json policy of permissions required by Terraform to the codebuild_policy parameter. This example provides permissions so Terraform can make IAM changes and also assume the `landing-iam-role` in any account.

```hcl
module "main-pipeline" {
  source = "github.com/ministryofjustice/analytical-platform-pipeline"

  name = "iam-pipeline"
  pipeline_github_repo = "analytical-platform-iam"
  pipeline_github_owner = "ministryofjustice"
  pipeline_github_branch = "main"
  codebuild_policy = "${data.aws_iam_policy_document.codebuild_policy.json}"
}

data "aws_iam_policy_document" "codebuild_policy" {
  statement {
    sid = "iamPermissions"
    actions = ["iam:*"]
    resources = ["*"]
  }

  statement {
    sid = "assumeLandingRole"
    actions = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::*:role/landing-iam-role"]
  }
}
```

### Variables

Default values are set for variables such as state bucket, state file kms key and state lock table. These variables are used to allow codebuild/codepipeline to access these resources e.g. to access the kms encrypted state file. If non-default resources are used, the values should be passed in to the module.

### Buildspec

#### buildspec-plan.yml

```YAML
version: 0.2

env:
  variables:
    TF_VERSION: "0.11.13"

phases:

  install:
    commands:
      - echo Downloading Terraform
      - cd /usr/bin
      - curl -s -qL -o terraform.zip https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip
      - unzip -o terraform.zip

  build:
    commands:
      - cd $CODEBUILD_SRC_DIR
      - terraform init -input=false
      - terraform plan -var-file=vars/landing.tfvars -out=tfplan -input=false
      - aws s3 cp tfplan s3://$PLAN_BUCKET/tfplan

  post_build:
    commands:
      - echo "terraform plan completed on `date`"
```

#### buildspec-apply.yml

```YAML
version: 0.2

env:
  variables:
    TF_VERSION: "0.11.13"

phases:

  install:
    commands:
      - echo Downloading Terraform
      - cd /usr/bin
      - curl -s -qL -o terraform.zip https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip
      - unzip -o terraform.zip

  build:
    commands:
      - cd $CODEBUILD_SRC_DIR
      - terraform init -input=false
      - aws s3 cp s3://$PLAN_BUCKET/tfplan tfplan
      - terraform apply -input=false tfplan

  post_build:
    commands:
      - echo "terraform plan completed on `date`"
```
