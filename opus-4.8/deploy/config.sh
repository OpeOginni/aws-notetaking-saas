#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# Central deployment configuration. Sourced by every deploy/*.sh script.
# Override any value by exporting it before running the scripts, e.g.:
#   AWS_REGION=us-east-1 ./deploy/deploy-all.sh
# ----------------------------------------------------------------------------
set -euo pipefail

# --- Naming -----------------------------------------------------------------
export PROJECT="${PROJECT:-notesaas}"
export AWS_REGION="${AWS_REGION:-eu-central-1}"

# Derived resource names (kept deterministic so re-runs are idempotent).
export ECR_REPO="${ECR_REPO:-${PROJECT}}"
export CLUSTER_NAME="${CLUSTER_NAME:-${PROJECT}-cluster}"
export SERVICE_NAME="${SERVICE_NAME:-${PROJECT}-service}"
export TASK_FAMILY="${TASK_FAMILY:-${PROJECT}-task}"
export ALB_NAME="${ALB_NAME:-${PROJECT}-alb}"
export TG_NAME="${TG_NAME:-${PROJECT}-tg}"
export LOG_GROUP="${LOG_GROUP:-/ecs/${PROJECT}}"
export CODEBUILD_PROJECT="${CODEBUILD_PROJECT:-${PROJECT}-build}"

# --- IAM role names ---------------------------------------------------------
export EXEC_ROLE_NAME="${EXEC_ROLE_NAME:-${PROJECT}-ecs-exec-role}"
export TASK_ROLE_NAME="${TASK_ROLE_NAME:-${PROJECT}-ecs-task-role}"
export CODEBUILD_ROLE_NAME="${CODEBUILD_ROLE_NAME:-${PROJECT}-codebuild-role}"

# --- Database ---------------------------------------------------------------
export DB_INSTANCE_ID="${DB_INSTANCE_ID:-${PROJECT}-db}"
export DB_NAME="${DB_NAME:-notesaas}"
export DB_USER="${DB_USER:-notesaas}"
export DB_INSTANCE_CLASS="${DB_INSTANCE_CLASS:-db.t3.micro}"
export DB_ALLOCATED_STORAGE="${DB_ALLOCATED_STORAGE:-20}"
export DB_ENGINE_VERSION="${DB_ENGINE_VERSION:-16}"

# --- S3 ---------------------------------------------------------------------
# Bucket names are globally unique, so suffix with the account id.
export S3_BUCKET_PREFIX="${S3_BUCKET_PREFIX:-${PROJECT}-uploads}"

# --- App container ----------------------------------------------------------
export APP_PORT="${APP_PORT:-3000}"
export TASK_CPU="${TASK_CPU:-512}"
export TASK_MEMORY="${TASK_MEMORY:-1024}"
export DESIRED_COUNT="${DESIRED_COUNT:-2}"
export IMAGE_TAG="${IMAGE_TAG:-latest}"
# Set to "true" only when the ALB is behind HTTPS (ACM cert). Default false so
# the HTTP load-balanced endpoint can set/read the session cookie.
export COOKIE_SECURE="${COOKIE_SECURE:-false}"

# --- State directory --------------------------------------------------------
# Resource identifiers discovered/created during deployment are written here so
# later scripts (and re-runs) can find them without guessing.
export STATE_DIR="${STATE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.state}"
mkdir -p "$STATE_DIR"

# --- Helpers ----------------------------------------------------------------
export ACCOUNT_ID="${ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
export ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"

# Persist a key=value into the state dir.
state_set() {
  local key="$1"; local val="$2"
  echo "$val" > "${STATE_DIR}/${key}"
}

# Read a value from the state dir (empty string if missing).
state_get() {
  local key="$1"
  if [ -f "${STATE_DIR}/${key}" ]; then cat "${STATE_DIR}/${key}"; else echo ""; fi
}

# All log output goes to stderr so it never pollutes $(...) command captures.
log()  { echo -e "\033[1;34m[deploy]\033[0m $*" >&2; }
warn() { echo -e "\033[1;33m[deploy]\033[0m $*" >&2; }
err()  { echo -e "\033[1;31m[deploy]\033[0m $*" >&2; }
