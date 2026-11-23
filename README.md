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

Tests use their own `job_matcher_ruby_test` database on the same server. Before each run, they rebuild jobscan's tables from the Flyway migrations copied into `db/jobscan_migrations/`. After jobscan adds a migration, copy them again with:

```sh
bin/sync-jobscan-migrations
```

## Job matching

A run matches open job postings discovered in the last week to the resume of each user with auto-analysis enabled. It sends each resume (a PDF in jobscan's resumes bucket, at the key in `resumes.file_link`) and the postings to Claude on Bedrock, and keeps the postings scoring 60 or more. Results are not stored: they are emailed or returned.

### From the command line

```sh
bin/rails job_matching:run
bin/rails job_matching:run USER_EMAIL=someone@example.com SINCE=2026-11-01
```

`USER_EMAIL` matches one user, whether or not auto-analysis is enabled. `SINCE` replaces the one-week window. Each user with matches is emailed, and every result is printed as JSON.

It needs AWS credentials and `RESUMES_BUCKET_NAME` (`jobscan-resumes-dev`). Locally, emails are only logged; set `MAIL_DELIVERY_METHOD=ses_v2` and `SES_SENDER_EMAIL` to send them through SES.

### From Claude Code (MCP)

The web server serves an MCP server at `/mcp` with two tools:

| Tool | Does |
|---|---|
| `match_jobs` | Runs the matching and returns the results. Optional `user_email`, `since` and `send_email` (defaults to false). |
| `refine_matches` | Revises one user's matches, as returned by `match_jobs`, following feedback such as "only remote jobs". |

Every request needs a Cognito access token from jobscan's user pool, issued to the backoffice SPA client to a user in the `admin` group. Locally, set `COGNITO_ISSUER_URI` and `COGNITO_SPA_CLIENT_ID` (see `terraform/dev.tfvars`). With the app reachable on port 3000, locally or through the SSM tunnel below:

```sh
claude mcp add --transport http job-matcher http://localhost:3000/mcp --header "Authorization: Bearer <access token>"
```

Access tokens expire after 60 minutes, so the header must then be replaced with a new token.

## Infrastructure

The `terraform/` stack runs in AWS `eu-west-1` (environment `dev`) next to jobscan. It reads jobscan's local state (`jobscan_state_path`), so **apply the jobscan stack first**.

| Component | Details |
|---|---|
| **Web server** | ECS service on its own EC2 instance (`t3.micro`, Auto Scaling group fixed at 1) in jobscan's public subnet. No inbound rules: reach it through SSM port forwarding on port 80. |
| **Batch matching** | Fargate task running `bin/rails job_matching:run`, started by an EventBridge Scheduler schedule. The schedule is `DISABLED` until a manual run has worked (`matching_schedule_state`). |
| **Database** | jobscan's RDS instance, as the read-only user `job_matcher_app` with IAM authentication (`DB_IAM_AUTH=true`, see `config/initializers/rds_iam_authentication.rb`). |
| **Permissions** | Read resumes from jobscan's S3 bucket, invoke the Bedrock inference profile `bedrock_inference_profile_id`, and send email through SES from `ses_sender_email`. |
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

3. Create the database user, as described in "Setting up the database user" below.

### Setting up the database user

Run this once, before the app's first deploy. Without the user, the app starts but fails its first database query. It doesn't depend on this stack, so it can also be done before `terraform apply`.

The app logs in to jobscan's RDS as `job_matcher_app` with an IAM token. That user has no password and can only read tables, so creating it doesn't affect jobscan.

You need the `session-manager-plugin` (see jobscan's README). If RDS was stopped with jobscan's `scripts/stop_environment.sh`, start it first.

1. Open a tunnel to RDS through jobscan's instance:
   ```sh
   RDS_HOST=$(terraform -chdir=../jobscan/terraform output -raw rds_endpoint | cut -d: -f1)
   ASG=$(terraform -chdir=../jobscan/terraform output -raw asg_name)
   INSTANCE_ID=$(aws ec2 describe-instances --region eu-west-1 \
     --filters "Name=tag:aws:autoscaling:groupName,Values=$ASG" "Name=instance-state-name,Values=running" \
     --query 'Reservations[0].Instances[0].InstanceId' --output text)

   aws ssm start-session --region eu-west-1 --target "$INSTANCE_ID" \
     --document-name AWS-StartPortForwardingSessionToRemoteHost \
     --parameters "{\"host\":[\"$RDS_HOST\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"5433\"]}"
   ```

2. In another terminal, connect as the master user (`db_username` in jobscan's `terraform/dev.tfvars`, `admin_user`). Its password is in the Secrets Manager secret that RDS manages. If `psql` isn't installed, run it from the Postgres image:
   ```sh
   SECRET_ARN=$(aws rds describe-db-instances --region eu-west-1 --db-instance-identifier jobscan-dev \
     --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text)
   export PGPASSWORD=$(aws secretsmanager get-secret-value --region eu-west-1 \
     --secret-id "$SECRET_ARN" --query SecretString --output text | jq -r .password)

   docker run --rm -it --network host -e PGPASSWORD postgres:16 \
     psql "host=localhost port=5433 dbname=jobscan user=admin_user sslmode=require"
   ```

3. Create the user, allow it to log in with IAM and let it read jobscan's tables:
   ```sql
   CREATE USER job_matcher_app;
   GRANT rds_iam TO job_matcher_app;
   GRANT USAGE ON SCHEMA public TO job_matcher_app;
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO job_matcher_app;
   ```

4. `GRANT SELECT ON ALL TABLES` only covers the tables that exist now. Check who owns them with `\dt`. If the owner is `jobscan_app`, which runs jobscan's Flyway migrations, make the tables it creates later readable too:
   ```sql
   GRANT jobscan_app TO admin_user;
   ALTER DEFAULT PRIVILEGES FOR ROLE jobscan_app IN SCHEMA public GRANT SELECT ON TABLES TO job_matcher_app;
   ```
   Otherwise, run the last `GRANT` from step 3 again after each jobscan migration that adds a table.

5. Check the user: `\du job_matcher_app` should list `rds_iam` in its "Member of" column.

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
