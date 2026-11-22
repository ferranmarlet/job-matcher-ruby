output "ecr_repository_url" {
  description = "ECR repository to push the application image to"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "web_service_name" {
  value = aws_ecs_service.web.name
}

output "asg_name" {
  description = "Auto Scaling group name, used to find the instance for SSM port forwarding"
  value       = aws_autoscaling_group.ecs.name
}

output "matching_task_definition" {
  description = "Task definition family of the batch matching task"
  value       = aws_ecs_task_definition.matching.family
}

output "rails_master_key_secret_id" {
  description = "Secret that must hold the contents of config/master.key"
  value       = aws_secretsmanager_secret.rails_master_key.id
}

output "rds_iam_db_user" {
  description = "Database user to create by hand on the jobscan RDS instance"
  value       = var.db_app_username
}
