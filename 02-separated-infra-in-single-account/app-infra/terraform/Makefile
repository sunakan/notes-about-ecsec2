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
