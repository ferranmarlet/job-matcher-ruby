variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Project name, used for naming and tagging resources"
  type        = string
  default     = "job-matcher"
}

variable "environment" {
  description = "Environment name, shared with the jobscan stack"
  type        = string
  default     = "dev"
}

variable "jobscan_state_path" {
  description = "Path to the jobscan stack's local state file, which owns the VPC, RDS and the resumes bucket"
  type        = string
  default     = "../../jobscan/terraform/terraform.tfstate"
}

variable "jobscan_project_name" {
  description = "project_name of the jobscan stack, used to find its resources by name"
  type        = string
  default     = "jobscan"
}

variable "db_app_username" {
  description = "Read-only database user that authenticates via IAM (created by hand, must be granted rds_iam)"
  type        = string
  default     = "job_matcher_app"
}

variable "instance_type" {
  description = "EC2 instance type that runs the web server"
  type        = string
  default     = "t3.micro"
}

variable "container_image_tag" {
  description = "Tag of the image in the ECR repository to deploy"
  type        = string
  default     = "latest"
}

variable "container_port" {
  description = "Port Thruster listens on inside the container"
  type        = number
  default     = 80
}

variable "bedrock_inference_profile_id" {
  description = "Bedrock cross-region inference profile used for matching"
  type        = string
  default     = "eu.anthropic.claude-sonnet-5-5"
}

variable "ses_sender_email" {
  description = "Address the match results are sent from. SES sends a verification email to it."
  type        = string
}

variable "ses_recipient_emails" {
  description = "Addresses to verify while the SES account is in the sandbox, where only verified recipients receive mail"
  type        = list(string)
  default     = []
}

variable "matching_schedule_expression" {
  description = "EventBridge Scheduler expression for the batch matching task"
  type        = string
  default     = "cron(0 7 * * ? *)"
}

variable "matching_schedule_timezone" {
  description = "Time zone of matching_schedule_expression"
  type        = string
  default     = "UTC"
}

variable "matching_schedule_state" {
  description = "ENABLED or DISABLED. Keep DISABLED until the job_matching:run task exists."
  type        = string
  default     = "DISABLED"
}
