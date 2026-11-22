# AI-powered job matcher

Job matching between job postings ingested from several job portals and the resumes that users upload.

## Database

The database belongs to [jobscan](../jobscan), which creates and migrates its tables with Flyway. This app only reads from it, so database tasks (`db:create`, `db:migrate`, ...) are disabled in development and production.

## Working locally

Start jobscan's PostgreSQL container, then run the app:

```sh
docker compose -f ../jobscan/compose.yaml up -d --wait postgres
bin/rails server
```

It connects to the `jobscan` database as `jobscan` / `jobscan` on `localhost:5432`. Override any of these with `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME` and `DB_PASSWORD`.

Tests use their own `job_matcher_ruby_test` database on the same server.

## Infrastructure

The `terraform/` stack runs in AWS `eu-west-1` (environment `dev`) next to jobscan. It reads jobscan's local state (`jobscan_state_path`), so **apply the jobscan stack first**.

| Component | Details |
|---|---|
| **Web server** | ECS service on its own EC2 instance (`t3.micro`, Auto Scaling group fixed at 1) in jobscan's public subnet. No inbound rules: reach it through SSM port forwarding on port 80. |
| **Batch matching** | Fargate task running `bin/rails job_matching:run`, started by an EventBridge Scheduler schedule. The schedule is `DISABLED` until that task exists (`matching_schedule_state`). |
| **Database** | jobscan's RDS instance, as the read-only user `job_matcher_app` with IAM authentication (`DB_IAM_AUTH=true`, see `config/initializers/rds_iam_authentication.rb`). |
| **Permissions** | Read resumes from jobscan's S3 bucket, invoke the Bedrock inference profile `bedrock_inference_profile_id`, send email through SES from `ses_sender_email`, and start the batch matching task. |
| **Secrets** | `RAILS_MASTER_KEY`, from a Secrets Manager secret whose value is set by hand. |

### First-time setup

1. Add the address the results are sent from to `terraform/dev.tfvars`. While the SES account is in the sandbox, also list every recipient:
   ```hcl
   ses_sender_email     = "<sender address>"
   ses_recipient_emails = ["<recipient address>"]
   ```
   SES emails each address a verification link, which must be clicked before it can send or receive.

2. Create the image repository, push the image, then create everything else:
   ```sh
   terraform -chdir=terraform init
   terraform -chdir=terraform apply -var-file=dev.tfvars -target=aws_ecr_repository.app -target=aws_secretsmanager_secret.rails_master_key
   aws secretsmanager put-secret-value --region eu-west-1 \
     --secret-id "$(terraform -chdir=terraform output -raw rails_master_key_secret_id)" \
     --secret-string "$(cat config/master.key)"
   ```
   Then push the image as described in "Deploying a new version", and run:
   ```sh
   terraform -chdir=terraform apply -var-file=dev.tfvars
   ```

3. Create the database user, through an SSM tunnel to RDS as described in jobscan's README, connected as the RDS master user:
   ```sql
   CREATE USER job_matcher_app;
   GRANT rds_iam TO job_matcher_app;
   GRANT USAGE ON SCHEMA public TO job_matcher_app;
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO job_matcher_app;
   ```
   `GRANT SELECT ON ALL TABLES` only covers existing tables. So that tables created later by jobscan's migrations are readable too, let the master user act for `jobscan_app`, which owns them, and set its default privileges:
   ```sql
   GRANT jobscan_app TO <master user>;
   ALTER DEFAULT PRIVILEGES FOR ROLE jobscan_app IN SCHEMA public GRANT SELECT ON TABLES TO job_matcher_app;
   ```

### Deploying a new version

```sh
ECR_URL=$(terraform -chdir=terraform output -raw ecr_repository_url)
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin "${ECR_URL%%/*}"
docker build --platform linux/amd64 -t "$ECR_URL:latest" .
docker push "$ECR_URL:latest"
aws ecs update-service --region eu-west-1 --force-new-deployment \
  --cluster "$(terraform -chdir=terraform output -raw ecs_cluster_name)" \
  --service "$(terraform -chdir=terraform output -raw web_service_name)"
```

### Reaching the web server

```sh
ASG=$(terraform -chdir=terraform output -raw asg_name)
INSTANCE_ID=$(aws ec2 describe-instances --region eu-west-1 \
  --filters "Name=tag:aws:autoscaling:groupName,Values=$ASG" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

aws ssm start-session --region eu-west-1 --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["80"],"localPortNumber":["3000"]}'
```

The app is then at http://localhost:3000.
