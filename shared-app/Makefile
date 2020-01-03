.env:
	cp env.sample .env
build: .env
	docker-compose build
up: .env
	docker-compose up
bash: .env
	docker-compose run --rm --service-ports app bash
curl:
	curl http://localhost:4567/
