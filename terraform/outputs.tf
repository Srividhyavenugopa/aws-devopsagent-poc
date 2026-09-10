output "ecr_repository_url" {
  description = "ECR repository URL - use this as ECR_URL secret in GitHub"
  value       = aws_ecr_repository.hello.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group - point DevOps Agent here"
  value       = aws_cloudwatch_log_group.hello.name
}
