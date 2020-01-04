secrets.tfvars:
	touch secrets.tfvars
plan: secrets.tfvars
	terraform plan -var-file=secrets.tfvars
apply: secrets.tfvars
	terraform apply -var-file=secrets.tfvars
refresh: secrets.tfvars
	terraform refresh -var-file=secrets.tfvars
init:
	terraform init
fmt:
	terraform fmt -recursive
destroy:
	terraform destroy

test:
	aws --profile sunabako-terraform-role sts get-caller-identity

export S3_BUCKET_NAME=foobar-shared-infra
make-bucket:
	aws --profile sunabako-terraform-role \
    s3api create-bucket \
      --bucket ${S3_BUCKET_NAME} \
      --region ap-northeast-1 \
      --create-bucket-configuration LocationConstraint=ap-northeast-1
	aws --profile sunabako-terraform-role \
    s3api put-public-access-block \
      --bucket ${S3_BUCKET_NAME} \
      --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
	aws --profile sunabako-terraform-role \
    s3api put-bucket-encryption \
      --bucket ${S3_BUCKET_NAME} \
      --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'

remove-bucket:
	aws --profile sunabako-terraform-role \
    s3 rb s3://${S3_BUCKET_NAME} \
      --force
