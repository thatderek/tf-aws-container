output "name" {
  description = "The name used by this module for deployed resources."
  value       = local.name
}

output "aws_ecr_repository" {
  value       = aws_ecr_repository.main
  description = "The AWS ECR Repository where the resulting image is held."
}

output "aws_cloudwatch_log_group" {
  value       = aws_cloudwatch_log_group.main
  description = "The CloudWatch Log Group where build logs are sent."
}

output "aws_ecr_image" {
  value       = data.aws_ecr_image.main
  description = "Details about the ECR image created by this repository."
}
