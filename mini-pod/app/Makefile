.env:
	cp env.sample .env
build: .env
	docker-compose build
up: .env
	docker-compose up
down:
	docker-compose down
bash: .env
	docker-compose run --rm --service-ports app bash
curl:
	curl http://localhost:4567/

build-image: .env
	bash ./build-image.sh | tail -1

# ECRがある前提
export PUSHER_AWS_PROFILE=sunabako-terraform-role
login:
	aws --profile ${PUSHER_AWS_PROFILE} ecr get-login --no-include-email | sh
push-image: .env login
	bash ./build-image.sh | tail -1 | bash ./push-image.sh
