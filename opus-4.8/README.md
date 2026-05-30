# NoteSaaS

A production-style, full-stack SaaS notes application deployed on AWS.

Users can sign up, log in, create / edit / delete notes, upload images and
files (stored in Amazon S3), and view a dashboard of their content. The app
runs on **AWS ECS Fargate** behind an **Application Load Balancer**, backed by
**RDS PostgreSQL**, with attachments in **S3**.

---

## Table of contents

1. [Architecture](#architecture)
2. [Tech stack](#tech-stack)
3. [Repository layout](#repository-layout)
4. [Local development](#local-development)
5. [Environment configuration](#environment-configuration)
6. [Production deployment (AWS)](#production-deployment-aws)
7. [Deployment scripts reference](#deployment-scripts-reference)
8. [Verifying the deployment](#verifying-the-deployment)
9. [Tearing everything down](#tearing-everything-down)

---

## Architecture

```
                          Internet
                              │
                       ┌──────▼───────┐
                       │  ALB (HTTP)  │  internet-facing, port 80
                       └──────┬───────┘
                              │ forward → target group :3000
                   ┌──────────▼───────────┐
                   │  ECS Fargate Service │  (2+ tasks, multi-AZ)
                   │  Next.js standalone  │
                   └─────┬───────────┬────┘
                         │           │
              task role  │           │  task role
        ┌────────────────▼┐        ┌─▼──────────────────┐
        │  RDS PostgreSQL │        │  S3 (private bucket)│
        │  (Drizzle ORM)  │        │  note attachments   │
        └─────────────────┘        └─────────────────────┘
```

- **ALB** terminates public HTTP traffic and load-balances across tasks.
- **ECS Fargate** runs the containerized Next.js server. On startup each task
  runs database migrations, then serves the app.
- **RDS PostgreSQL** stores users, notes, and attachment metadata. Credentials
  live in **AWS Secrets Manager**.
- **S3** stores the actual uploaded files (private; served through the app via
  an authenticated proxy route, never exposed publicly).
- **CodeBuild** builds and pushes the Docker image to **ECR** (no local Docker
  daemon required).

## Tech stack

| Layer        | Choice                                   |
|--------------|------------------------------------------|
| Framework    | Next.js 15 (App Router, standalone)      |
| Language     | TypeScript / React 19                    |
| ORM          | Drizzle ORM + `postgres` driver          |
| Database     | PostgreSQL 16 (RDS)                       |
| Auth         | Email + password, bcrypt, JWT sessions (`jose`) in httpOnly cookies |
| File storage | Amazon S3 (`@aws-sdk/client-s3`)         |
| Container    | Docker (multi-stage, node:22-alpine)     |
| Compute      | AWS ECS Fargate                          |
| Networking   | Application Load Balancer                |
| IaC / deploy | AWS CLI shell scripts (idempotent)       |

## Repository layout

```
opus-4.8/
├── src/
│   ├── app/                # Next.js App Router pages + API routes
│   │   ├── api/            # auth, notes, attachments, health endpoints
│   │   ├── dashboard/      # protected dashboard + note editor
│   │   ├── login/ signup/  # auth pages
│   │   └── page.tsx        # landing page
│   ├── db/                 # Drizzle schema, client, migrate runner
│   ├── lib/                # auth, s3 helpers
│   └── middleware.ts       # route protection
├── drizzle/                # generated SQL migrations
├── scripts/migrate.mjs     # runtime migration runner (used in container)
├── deploy/                 # AWS deployment scripts (see below)
├── Dockerfile              # multi-stage production image
├── docker-entrypoint.sh    # migrate + start
├── docker-compose.yml      # local Postgres
├── drizzle.config.ts
└── .env.example
```

---

## Local development

### Prerequisites

- Node.js 20+ (or [Bun](https://bun.sh))
- Docker (only for the local Postgres container) **or** a local PostgreSQL 16
- AWS credentials (only if you want to test real S3 uploads locally)

### Steps

```bash
# 1. Install dependencies
npm install            # or: bun install

# 2. Start a local PostgreSQL
docker compose up -d db

# 3. Configure environment
cp .env.example .env
#   For local dev the defaults work:
#   DATABASE_URL=postgres://postgres:postgres@localhost:5432/notesaas
#   DATABASE_SSL=false
#   AUTH_SECRET=<any 16+ char string>   (e.g. `openssl rand -base64 32`)
#   Leave S3_BUCKET empty to disable uploads, or set it to a bucket you can
#   access with your local AWS credentials.

# 4. Apply database migrations
npm run db:migrate

# 5. Run the dev server
npm run dev
```

Open <http://localhost:3000>. Sign up, create a note, attach files.

### Useful scripts

| Command               | Description                                  |
|-----------------------|----------------------------------------------|
| `npm run dev`         | Start Next.js dev server                     |
| `npm run build`       | Production build                             |
| `npm run start`       | Run the production build                     |
| `npm run db:generate` | Generate a new SQL migration from the schema |
| `npm run db:migrate`  | Apply migrations                             |
| `npm run db:push`     | Push schema directly (dev convenience)       |

---

## Environment configuration

All variables are documented in [`.env.example`](./.env.example).

| Variable            | Required | Description |
|---------------------|----------|-------------|
| `DATABASE_URL`      | yes      | PostgreSQL connection string. Locally points at the docker Postgres; in production it is generated from the RDS endpoint by the deploy scripts. |
| `DATABASE_SSL`      | no       | `false` to disable TLS (local). Anything else / unset enables TLS (required by RDS). |
| `AUTH_SECRET`       | yes      | Secret used to sign session JWTs. Min 16 chars. Generate with `openssl rand -base64 32`. In production it is auto-generated and stored in the deploy state. |
| `AWS_REGION`        | yes      | Region of the S3 bucket (default `eu-central-1`). |
| `S3_BUCKET`         | yes\*    | Bucket name for attachments. Created by the deploy scripts. \*Optional locally (uploads disabled if empty). |
| `NODE_ENV`          | no       | `development` locally; deploy sets `production`. |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | local only | Only needed locally for real S3. In ECS the **task role** supplies credentials automatically. |

---

## Production deployment (AWS)

### Prerequisites

- **AWS CLI v2** configured with credentials that can create VPC/EC2 SGs, IAM,
  RDS, S3, ECR, CodeBuild, ECS, and ELBv2 resources.
- `zip` and `bash` available locally.
- **No local Docker required** — the image is built in AWS CodeBuild.

### One command

```bash
./deploy/deploy-all.sh
```

This runs every step in order (network → S3 → IAM → RDS → image build → ECS →
verify). When it finishes it prints the public URL:

```
[deploy] Deployment complete!
[deploy] URL: http://notesaas-alb-XXXXXXXX.eu-central-1.elb.amazonaws.com
```

Every step is **idempotent**, so you can re-run `deploy-all.sh` safely (e.g.
after changing code — it rebuilds the image and forces a new ECS deployment).

### Configuration overrides

Any value in `deploy/config.sh` can be overridden via environment variables:

```bash
AWS_REGION=us-east-1 DESIRED_COUNT=3 DB_INSTANCE_CLASS=db.t3.small \
  ./deploy/deploy-all.sh
```

### Redeploying after code changes

```bash
./deploy/05-build-image.sh   # rebuild + push image
./deploy/06-ecs.sh           # register new task def + force new deployment
./deploy/07-verify.sh        # wait for healthy + probe
```

---

## Deployment scripts reference

| Script                 | Responsibility |
|------------------------|----------------|
| `config.sh`            | Central configuration + state helpers (sourced by all). |
| `01-network.sh`        | Discovers default VPC/subnets; creates ALB / ECS / RDS security groups with least-privilege ingress. |
| `02-iam.sh`            | Creates ECS task-execution role, ECS task role (scoped S3 access), and CodeBuild role. |
| `03-s3.sh`             | Creates the private, encrypted uploads bucket with public access blocked. |
| `04-rds.sh`            | Provisions RDS PostgreSQL, generates credentials, stores them in Secrets Manager, writes `DATABASE_URL`. |
| `05-build-image.sh`    | Ensures ECR repo; zips source to S3; runs CodeBuild to build & push the Docker image. |
| `06-ecs.sh`            | Creates ALB + target group + listener; registers the task definition; creates/updates the Fargate service. |
| `07-verify.sh`         | Waits for service stability + healthy targets; probes `/api/health`. |
| `deploy-all.sh`        | Runs all of the above in order. |
| `destroy.sh`           | Tears down every created resource (prompts for confirmation). |
| `buildspec.yml`        | CodeBuild instructions to build & push the image. |

State (resource IDs, endpoints, secrets) is written to `deploy/.state/` so
re-runs and later steps can discover prior resources. This directory is
git-ignored.

---

## Verifying the deployment

The deploy prints the ALB URL. To verify manually:

```bash
URL="http://$(cat deploy/.state/alb_dns)"

# Health check
curl "$URL/api/health"        # => {"status":"ok",...}

# Then in a browser:
#  1. Open $URL  → landing page
#  2. Sign up    → redirected to /dashboard
#  3. Create a note, type content (autosaves)
#  4. Upload an image/file → appears as an attachment
#  5. Log out / log back in → data persists (RDS)
```

CloudWatch logs for the running tasks are in the log group `/ecs/notesaas`.

---

## Tearing everything down

```bash
./deploy/destroy.sh        # type "destroy" to confirm
```

Removes the ECS service/cluster, ALB, target group, RDS instance + subnet
group, Secrets Manager secret, S3 buckets, CodeBuild project, ECR repo,
CloudWatch logs, security groups, and IAM roles.
