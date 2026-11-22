aws_region      = "eu-west-1"
project_name    = "job-matcher"
environment     = "dev"
db_app_username = "job_matcher_app"
instance_type   = "t3.micro"

bedrock_inference_profile_id = "eu.anthropic.claude-sonnet-5-5"

matching_schedule_expression = "cron(0 7 * * ? *)"
matching_schedule_timezone   = "UTC"
matching_schedule_state      = "DISABLED"
