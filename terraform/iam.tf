# --- EC2 host ---
resource "aws_iam_role" "ecs_instance" {
  name = "${local.name}-ecs-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ecs" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Lets the instance accept SSM sessions, used for port forwarding
resource "aws_iam_role_policy_attachment" "ecs_instance_ssm" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "${local.name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name
}

# --- ECS agent: pulls the image, writes logs, injects secrets ---
resource "aws_iam_role" "task_execution" {
  name = "${local.name}-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  name = "read-rails-master-key"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_secretsmanager_secret.rails_master_key.arn
    }]
  })
}

# --- The running app, shared by the web server and the batch task ---
resource "aws_iam_role" "app_task" {
  name = "${local.name}-app-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "app_task_rds" {
  name = "rds-iam-auth"
  role = aws_iam_role.app_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "rds-db:connect"
      Resource = "arn:aws:rds-db:${var.aws_region}:${data.aws_caller_identity.current.account_id}:dbuser:${data.aws_db_instance.jobscan.resource_id}/${var.db_app_username}"
    }]
  })
}

resource "aws_iam_role_policy" "app_task_resumes" {
  name = "resumes-bucket-read"
  role = aws_iam_role.app_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${data.aws_s3_bucket.resumes.arn}/*"
      },
      {
        # Without it, reading a missing key returns 403 instead of 404
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = data.aws_s3_bucket.resumes.arn
      },
    ]
  })
}

data "aws_bedrock_inference_profile" "matching" {
  inference_profile_id = var.bedrock_inference_profile_id
}

# A cross-region profile routes each request to one of its regions' foundation models
resource "aws_iam_role_policy" "app_task_bedrock" {
  name = "bedrock-invoke"
  role = aws_iam_role.app_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
      Resource = concat(
        [data.aws_bedrock_inference_profile.matching.inference_profile_arn],
        data.aws_bedrock_inference_profile.matching.models[*].model_arn,
      )
    }]
  })
}

resource "aws_iam_role_policy" "app_task_ses" {
  name = "ses-send"
  role = aws_iam_role.app_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ses:SendEmail", "ses:SendRawEmail"]
      Resource = "arn:aws:ses:${var.aws_region}:${data.aws_caller_identity.current.account_id}:identity/*"
      Condition = {
        StringEquals = { "ses:FromAddress" = var.ses_sender_email }
      }
    }]
  })
}

# --- EventBridge Scheduler ---
resource "aws_iam_role" "scheduler" {
  name = "${local.name}-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "scheduler.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler_run_matching" {
  name = "run-matching-task"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "ecs:RunTask"
        Resource  = "${aws_ecs_task_definition.matching.arn_without_revision}:*"
        Condition = { ArnEquals = { "ecs:cluster" = aws_ecs_cluster.main.arn } }
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [aws_iam_role.task_execution.arn, aws_iam_role.app_task.arn]
      },
    ]
  })
}
