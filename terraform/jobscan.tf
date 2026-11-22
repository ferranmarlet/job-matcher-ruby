# Resources owned by the jobscan stack. Apply that stack first.
data "terraform_remote_state" "jobscan" {
  backend = "local"

  config = {
    path = var.jobscan_state_path
  }
}

data "aws_caller_identity" "current" {}

data "aws_subnet" "jobscan_public" {
  vpc_id = data.terraform_remote_state.jobscan.outputs.vpc_id

  filter {
    name   = "tag:Name"
    values = ["${var.jobscan_project_name}-public-a"]
  }
}

data "aws_db_instance" "jobscan" {
  db_instance_identifier = "${var.jobscan_project_name}-${var.environment}"
}

data "aws_s3_bucket" "resumes" {
  bucket = data.terraform_remote_state.jobscan.outputs.resumes_bucket_name
}

locals {
  name                       = "${var.project_name}-${var.environment}"
  vpc_id                     = data.terraform_remote_state.jobscan.outputs.vpc_id
  public_subnet_id           = data.aws_subnet.jobscan_public.id
  jobscan_app_security_group = data.terraform_remote_state.jobscan.outputs.app_security_group_id
  db_host                    = data.aws_db_instance.jobscan.address
  db_port                    = data.aws_db_instance.jobscan.port
  db_name                    = data.terraform_remote_state.jobscan.outputs.rds_db_name
}
