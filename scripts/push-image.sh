#!/bin/bash
set -e

REGION=${AWS_REGION:-us-east-1}
ECR_URL=$(cd ../terraform && terraform output -raw ecr_repository_url)

echo "Logging into ECR..."
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ECR_URL

echo "Building image..."
cd ../app
docker build --platform linux/amd64 -t hello-devops .

echo "Tagging and pushing..."
docker tag hello-devops:latest $ECR_URL:latest
docker push $ECR_URL:latest

echo "Done! Image pushed to: $ECR_URL:latest"

echo "Forcing ECS service redeploy..."
aws ecs update-service \
  --cluster hello-devops-cluster \
  --service hello-devops-service \
  --force-new-deployment \
  --region $REGION \
  --output json > /dev/null

echo "Redeploy triggered. Watch task status with:"
echo "  aws ecs list-tasks --cluster hello-devops-cluster --region $REGION"
