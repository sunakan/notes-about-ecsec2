#!/bin/bash

# -u 未定義変数を使うとError
# -e -o pipefail 途中でエラーが起きると、exit
set -u
set -e -o pipefail

# 定数
readonly AWS_ECR_REPO_NAME=sunatra

# DOCKER_IMAGE_WITH_TAGが未定義なら、標準入力で読み込む
if [ -z "${DOCKER_IMAGE_WITH_TAG:+DOCKER_IMAGE_WITH_TAG}" ]; then
    read DOCKER_IMAGE_WITH_TAG
fi

# AWS_ECR_REGISTRYが未定義なら、ACCOUNT_IDを取得して作る(手動用)
if [ -z "${AWS_ECR_REGISTRY:+$AWS_ECR_REGISTRY}" ]; then
  readonly AWS_ACCOUNT_ID=`aws --profile ${PUSHER_AWS_PROFILE} sts get-caller-identity | jq -r '.Account'`
  readonly AWS_REGION=ap-northeast-1
  readonly AWS_ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
fi

# push
docker tag ${DOCKER_IMAGE_WITH_TAG} ${AWS_ECR_REGISTRY}/${AWS_ECR_REPO_NAME}:${DOCKER_IMAGE_WITH_TAG##*:}
docker tag ${DOCKER_IMAGE_WITH_TAG} ${AWS_ECR_REGISTRY}/${AWS_ECR_REPO_NAME}:${ENV}
docker push ${AWS_ECR_REGISTRY}/${AWS_ECR_REPO_NAME}:${DOCKER_IMAGE_WITH_TAG##*:}
docker push ${AWS_ECR_REGISTRY}/${AWS_ECR_REPO_NAME}:${ENV}
docker image rm ${AWS_ECR_REGISTRY}/${AWS_ECR_REPO_NAME}:${DOCKER_IMAGE_WITH_TAG##*:}
docker image rm ${AWS_ECR_REGISTRY}/${AWS_ECR_REPO_NAME}:${ENV}
