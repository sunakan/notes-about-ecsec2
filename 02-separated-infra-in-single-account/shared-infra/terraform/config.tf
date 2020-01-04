################################################################################
# terraform init する前にS3バケットが必要
#   - 最初はコメントアウトしてlocalで色々実行して、コメントインしてもう一回initしてyes押してもよい
#   - profileがvarより先に展開されてしまうのでベタ打ち
#     - $ terraform init -backend-config="profile=${aws_profile}"
#     - とかでもいいかもしれない
################################################################################
terraform {
  required_version = "0.12.18"
  backend "s3" {
    bucket  = "foobar-shared-infra"
    region  = "ap-northeast-1"
    key     = "02-separated-infra-in-single-account/terraform.tfstate"
    encrypt = true
    profile = "sunabako-terraform-role"
  }
}

provider "aws" {
  version = "2.43.0"
  region  = "ap-northeast-1"
  profile = var.target_aws_account_profile
}

################################################################################
# ~/.aws/credentialで[AWS_PROFILE]を設定済みを前提
# xxxx.tfvarsで以下のように上書きする
# target_aws_account_profile = "AWS_PROFILE"
# RoleChainもprofile側で可能
################################################################################
variable "target_aws_account_profile" {
  description = "Terraformされる側のAWSアカウントのTerraform用のIAMUserとしてのプロフィール名"
  type        = string
  default     = "AWS_PROFILE"
}
