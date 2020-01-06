#!/bin/bash

DOCKER_IMAGE=nginx-sidecar

docker build -t ${DOCKER_IMAGE}:latest .

echo "Built docker image."
echo "${DOCKER_IMAGE}:latest"
