variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Deployment environment: dev, uat or prod"
  type        = string

  validation {
    condition     = contains(["dev", "uat", "prod"], var.environment)
    error_message = "environment must be one of: dev, uat, prod."
  }
}

variable "function_name" {
  description = "Base name for the Lambda function (environment is appended)"
  type        = string
  default     = "cloudops-ai-app"
}

variable "bedrock_model_id" {
  description = "Claude model used by the agent on Amazon Bedrock"
  type        = string
  default     = "anthropic.claude-haiku-4-5" # cheapest Claude, open to all Bedrock accounts
}

variable "langfuse_base_url" {
  description = "Langfuse region the agent sends traces to (EU by default; US: https://us.cloud.langfuse.com)"
  type        = string
  default     = "https://cloud.langfuse.com"
}

variable "github_repository" {
  description = "owner/repo the PR Lambda opens fix pull requests against"
  type        = string
  default     = "RayanAAY-ops/cloud-ai-ops"
}

variable "github_base_branch" {
  description = "Branch the fix pull requests target"
  type        = string
  default     = "main"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table used by the Lambda (shop-items)"
  type        = string
  default     = "shop-items"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention (days) for the Lambda's log group"
  type        = number
  default     = 30
}

variable "lambda_memory_mb" {
  description = "Memory allocated to the Lambda function, in MB"
  type        = number
  default     = 128
}

variable "lambda_timeout_seconds" {
  description = "Lambda function timeout, in seconds"
  type        = number
  default     = 10
}
