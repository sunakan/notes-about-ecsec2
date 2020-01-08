#!/bin/bash

# -u オプションは未定義変数を使うとError
# -e -o pipefail 途中でエラーが起きると、exit
set -u
set -e -o pipefail

readonly DOCKER_IMAGE=nginx-sidecar

# コミットIDの最初の8文字
COMMIT_ID=`git show -s --format=%H`
COMMIT_ID=${COMMIT_ID:0:8}
readonly IMAGE_TAG=${COMMIT_ID}

docker build ./ --tag ${DOCKER_IMAGE}:latest
docker tag ${DOCKER_IMAGE}:latest ${DOCKER_IMAGE}:${IMAGE_TAG}

# 次の処理にパイプで渡せるように、dockerimage:tagを標準出力
echo "Built docker image"
echo ${DOCKER_IMAGE}:${IMAGE_TAG}
