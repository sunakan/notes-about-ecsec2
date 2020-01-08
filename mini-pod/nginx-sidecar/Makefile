build:
	bash build-image.sh

# ECRがある前提
export PUSHER_AWS_PROFILE=sunabako-terraform-role
login:
	aws --profile ${PUSHER_AWS_PROFILE} ecr get-login --no-include-email | sh
push-image: .env login
	bash ./build-image.sh | tail -1 | bash ./push-image.sh
