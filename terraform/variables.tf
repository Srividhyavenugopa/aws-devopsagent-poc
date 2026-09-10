variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Application name (used for naming all resources)"
  type        = string
  default     = "hello-devops"
}
