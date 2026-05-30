# Fieldnotes Cloud

A production-style full-stack SaaS notes application built with Next.js, PostgreSQL, Drizzle ORM, S3 file storage, and AWS ECS behind an Application Load Balancer.

## Features

- Email/password sign-up and login with HTTP-only session cookies.
- Authenticated dashboard for creating, editing, and deleting notes.
- PostgreSQL persistence through Drizzle ORM schema definitions.
- Private S3 uploads attached to notes and streamed back only to the owning user.
- Docker production image using Next.js standalone output.
- Reproducible AWS deployment scripts for VPC, RDS PostgreSQL, S3, ECR, ECS Fargate, IAM, CloudWatch Logs, and ALB.

## Environment Variables

Copy `.env.example` to `.env.local` for local development.

| Variable | Required | Description |
| --- | --- | --- |
| `DATABASE_URL` | Yes | PostgreSQL connection string used by Drizzle and migrations. |
| `DB_SSL` | Yes | Use `false` for local Docker PostgreSQL and `true` for AWS RDS. |
| `AWS_REGION` | Yes | AWS region for S3 and deployment scripts. Defaults are designed for `eu-central-1`. |
| `S3_BUCKET_NAME` | Yes | Private bucket where note attachments are stored. Deployment writes the real value to `deployment-outputs.env`. |
| `COOKIE_SECURE` | No | Set `true` only behind HTTPS. Leave `false` for the provided HTTP ALB endpoint so login cookies work. |
| `APP_URL` | No | Public application origin used for route-handler redirects. Deployment sets this from `PUBLIC_URL`. |

## Local Development

Required dependencies:

- Node.js 22+
- npm
- Docker and Docker Compose for local PostgreSQL
- AWS credentials only if you want to test S3 uploads locally against a real bucket

Run locally:

```bash
cp .env.example .env.local
docker compose up -d postgres
npm install
npm run db:migrate
npm run dev
```

Open `http://localhost:3000`.

Local S3 uploads need `S3_BUCKET_NAME`, `AWS_REGION`, and AWS credentials in your shell. The application keeps objects private and serves them through authenticated `/api/files/[id]` requests.

## Production Deployment

The scripts are in `infra/aws-cli` and are intentionally parameterized with environment variables. Defaults deploy to `eu-central-1` with `APP_NAME=gpt55-notes`.

Deploy infrastructure:

```bash
AWS_REGION=eu-central-1 APP_NAME=gpt55-notes ./infra/aws-cli/deploy-infra.sh
```

This creates:

- Dedicated VPC with two public subnets and an internet gateway.
- Security groups for ALB, ECS tasks, and RDS.
- RDS PostgreSQL instance.
- Private encrypted S3 uploads bucket.
- ECR repository.
- ECS cluster, IAM task roles, CloudWatch log group.
- Public Application Load Balancer, listener, and target group.

The script writes `deployment-outputs.env`, including `DATABASE_URL`, `S3_BUCKET_NAME`, ECS identifiers, and `PUBLIC_URL`.

Build and deploy the app:

```bash
./infra/aws-cli/build-and-deploy-app.sh
```

This builds the Docker image, pushes it to ECR, registers an ECS Fargate task definition, creates or updates the service, points the ALB listener at the target group, and waits for service stability.

If Docker is not installed locally, the script automatically uploads the source bundle to S3 and uses AWS CodeBuild with privileged Docker mode to build and push the image.

Verify deployment:

```bash
./infra/aws-cli/verify.sh
```

The script checks `PUBLIC_URL/health`. After it passes, visit the printed public URL, create an account, create a note, upload a file, and open the attachment link.

Destroy deployment:

```bash
./infra/aws-cli/destroy.sh
```

The destroy script scales down and deletes the ECS service, empties the S3 bucket, and deletes the CloudFormation stack.

## Reproducibility Notes

- `infra/cloudformation/base.yml` is the source of truth for AWS infrastructure.
- `drizzle/0000_initial.sql` is run automatically when the container starts and can also be run locally with `npm run db:migrate`.
- `Dockerfile` packages the standalone Next.js server and migration script into one deployable artifact.
- `deployment-outputs.env` is generated and intentionally ignored by git because it contains the generated database password.
