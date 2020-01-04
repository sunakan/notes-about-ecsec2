terraform {
  required_version = "0.12.18"
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
