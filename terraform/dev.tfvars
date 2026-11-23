aws_region      = "eu-west-1"
project_name    = "job-matcher"
environment     = "dev"
db_app_username = "job_matcher_app"
instance_type   = "t3.micro"

bedrock_inference_profile_id = "eu.anthropic.claude-haiku-5-5"

matching_schedule_expression = "cron(0 7 * * ? *)"
matching_schedule_timezone   = "UTC"
matching_schedule_state      = "DISABLED"

cognito_issuer_uri    = "https://cognito-idp.eu-west-1.amazonaws.com/eu-west-1_Ux4AOlLZv"
cognito_spa_client_id = "71ep19rin2p202o9d546vvul8c"
