#!/bin/bash
set -e

REGION=${AWS_REGION:-us-east-1}
ECR_URL=$(cd ../terraform && terraform output -raw ecr_repository_url)

echo "Logging into ECR..."
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ECR_URL

echo "Building image..."
cd ../app
docker build -t hello-devops .

echo "Tagging and pushing..."
docker tag hello-devops:latest $ECR_URL:latest
docker push $ECR_URL:latest

echo "Done! Image pushed to: $ECR_URL:latest"
