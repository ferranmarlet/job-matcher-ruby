# No inbound rules: the web server is private, reach it through SSM port forwarding.
resource "aws_security_group" "app" {
  name        = "${local.name}-sg"
  description = "job-matcher web server and batch tasks"
  vpc_id      = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }
}

resource "aws_ecs_cluster" "main" {
  name = "${local.name}-cluster"
}

resource "aws_ecr_repository" "app" {
  name                 = local.name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the 5 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name}"
  retention_in_days = 7
}

# Value set by hand from config/master.key, so it never reaches the Terraform state
resource "aws_secretsmanager_secret" "rails_master_key" {
  name = "${local.name}/rails-master-key"
}

# --- EC2 host for the web server ---
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

resource "aws_launch_template" "ecs" {
  name_prefix   = "${local.name}-lt"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance.name
  }

  # Public IP for outbound traffic only: the VPC has no NAT gateway
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app.id, local.jobscan_app_security_group]
  }

  metadata_options {
    http_tokens = "required"
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config
  EOF
  )
}

resource "aws_autoscaling_group" "ecs" {
  name                = "${local.name}-asg"
  desired_capacity    = 1
  min_size            = 1
  max_size            = 1
  vpc_zone_identifier = [local.public_subnet_id]

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-web"
    propagate_at_launch = true
  }
}

# --- Task definitions ---
locals {
  image = "${aws_ecr_repository.app.repository_url}:${var.container_image_tag}"

  app_environment = [
    { name = "AWS_REGION", value = var.aws_region },
    { name = "DB_HOST", value = local.db_host },
    { name = "DB_PORT", value = tostring(local.db_port) },
    { name = "DB_NAME", value = local.db_name },
    { name = "DB_USERNAME", value = var.db_app_username },
    { name = "DB_IAM_AUTH", value = "true" },
    { name = "RESUMES_BUCKET_NAME", value = data.aws_s3_bucket.resumes.bucket },
    { name = "BEDROCK_INFERENCE_PROFILE_ID", value = var.bedrock_inference_profile_id },
    { name = "SES_SENDER_EMAIL", value = var.ses_sender_email },
    { name = "COGNITO_ISSUER_URI", value = var.cognito_issuer_uri },
    { name = "COGNITO_SPA_CLIENT_ID", value = var.cognito_spa_client_id },
    # Matching every user in one MCP request outlasts Thruster's 30-second default
    { name = "HTTP_WRITE_TIMEOUT", value = "600" },
  ]

  app_secrets = [{
    name      = "RAILS_MASTER_KEY"
    valueFrom = aws_secretsmanager_secret.rails_master_key.arn
  }]

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.app.name
      awslogs-region        = var.aws_region
      awslogs-stream-prefix = "ecs"
    }
  }
}

resource "aws_ecs_task_definition" "web" {
  family                   = "${var.project_name}-web"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.app_task.arn

  container_definitions = jsonencode([{
    name      = "web"
    image     = local.image
    cpu       = 1024
    memory    = 768
    essential = true
    portMappings = [{
      containerPort = var.container_port
      hostPort      = var.container_port
      protocol      = "tcp"
    }]
    environment      = local.app_environment
    secrets          = local.app_secrets
    logConfiguration = local.log_configuration
  }])
}

resource "aws_ecs_task_definition" "matching" {
  family                   = "${var.project_name}-matching"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.app_task.arn

  container_definitions = jsonencode([{
    name             = "matching"
    image            = local.image
    essential        = true
    command          = ["./bin/rails", "job_matching:run"]
    environment      = local.app_environment
    secrets          = local.app_secrets
    logConfiguration = local.log_configuration
  }])
}

resource "aws_ecs_service" "web" {
  name            = "${local.name}-web"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
  launch_type     = "EC2"

  # The single instance can't run two tasks on the same host port,
  # so stop the old task before starting the new one.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
}

# --- Scheduled batch matching ---
resource "aws_scheduler_schedule" "matching" {
  name                         = "${local.name}-matching"
  schedule_expression          = var.matching_schedule_expression
  schedule_expression_timezone = var.matching_schedule_timezone
  state                        = var.matching_schedule_state

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_ecs_cluster.main.arn
    role_arn = aws_iam_role.scheduler.arn

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.matching.arn_without_revision
      launch_type         = "FARGATE"

      network_configuration {
        subnets          = [local.public_subnet_id]
        security_groups  = [aws_security_group.app.id, local.jobscan_app_security_group]
        assign_public_ip = true
      }
    }

    retry_policy {
      maximum_retry_attempts = 0
    }
  }
}

# --- SES (account is in the sandbox: senders and recipients must be verified) ---
resource "aws_sesv2_email_identity" "sender" {
  email_identity = var.ses_sender_email
}

resource "aws_sesv2_email_identity" "sandbox_recipients" {
  for_each       = toset(var.ses_recipient_emails)
  email_identity = each.value
}
