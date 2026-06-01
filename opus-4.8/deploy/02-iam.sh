#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# 02-iam.sh
# Creates IAM roles:
#   - ECS task execution role (pull image, write logs, read secrets)
#   - ECS task role (app runtime perms: S3 access to the uploads bucket)
#   - CodeBuild role (build & push the image to ECR)
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

ecs_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
cb_trust='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codebuild.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

ensure_role() {
  local name="$1"; local trust="$2"
  if aws iam get-role --role-name "$name" >/dev/null 2>&1; then
    log "IAM role $name already exists"
  else
    aws iam create-role --role-name "$name" \
      --assume-role-policy-document "$trust" >/dev/null
    log "Created IAM role $name"
  fi
}

# --- Execution role ---------------------------------------------------------
ensure_role "$EXEC_ROLE_NAME" "$ecs_trust"
aws iam attach-role-policy --role-name "$EXEC_ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy >/dev/null 2>&1 || true
# Allow reading the DB secret from Secrets Manager.
aws iam put-role-policy --role-name "$EXEC_ROLE_NAME" \
  --policy-name "${PROJECT}-secrets-read" \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"secretsmanager:GetSecretValue\"],\"Resource\":\"arn:aws:secretsmanager:${AWS_REGION}:${ACCOUNT_ID}:secret:${PROJECT}-*\"}]}" >/dev/null
EXEC_ROLE_ARN=$(aws iam get-role --role-name "$EXEC_ROLE_NAME" --query 'Role.Arn' --output text)
state_set exec_role_arn "$EXEC_ROLE_ARN"

# --- Task role (app runtime: S3) --------------------------------------------
ensure_role "$TASK_ROLE_NAME" "$ecs_trust"
BUCKET=$(state_get s3_bucket)
BUCKET_RES="*"
if [ -n "$BUCKET" ]; then
  BUCKET_RES="arn:aws:s3:::${BUCKET}/*"
fi
aws iam put-role-policy --role-name "$TASK_ROLE_NAME" \
  --policy-name "${PROJECT}-s3-access" \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:PutObject\",\"s3:GetObject\",\"s3:DeleteObject\"],\"Resource\":\"${BUCKET_RES}\"},{\"Effect\":\"Allow\",\"Action\":[\"s3:ListBucket\"],\"Resource\":\"arn:aws:s3:::${PROJECT}-uploads-*\"}]}" >/dev/null
TASK_ROLE_ARN=$(aws iam get-role --role-name "$TASK_ROLE_NAME" --query 'Role.Arn' --output text)
state_set task_role_arn "$TASK_ROLE_ARN"

# --- CodeBuild role ---------------------------------------------------------
ensure_role "$CODEBUILD_ROLE_NAME" "$cb_trust"
aws iam put-role-policy --role-name "$CODEBUILD_ROLE_NAME" \
  --policy-name "${PROJECT}-codebuild-policy" \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[
    {\"Effect\":\"Allow\",\"Action\":[\"logs:CreateLogGroup\",\"logs:CreateLogStream\",\"logs:PutLogEvents\"],\"Resource\":\"*\"},
    {\"Effect\":\"Allow\",\"Action\":[\"ecr:GetAuthorizationToken\"],\"Resource\":\"*\"},
    {\"Effect\":\"Allow\",\"Action\":[\"ecr:BatchCheckLayerAvailability\",\"ecr:CompleteLayerUpload\",\"ecr:InitiateLayerUpload\",\"ecr:PutImage\",\"ecr:UploadLayerPart\",\"ecr:BatchGetImage\",\"ecr:GetDownloadUrlForLayer\"],\"Resource\":\"arn:aws:ecr:${AWS_REGION}:${ACCOUNT_ID}:repository/${ECR_REPO}\"},
    {\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:GetObjectVersion\",\"s3:PutObject\"],\"Resource\":\"arn:aws:s3:::${PROJECT}-build-*/*\"}
  ]}" >/dev/null
CODEBUILD_ROLE_ARN=$(aws iam get-role --role-name "$CODEBUILD_ROLE_NAME" --query 'Role.Arn' --output text)
state_set codebuild_role_arn "$CODEBUILD_ROLE_ARN"

log "IAM setup complete."
log "  EXEC_ROLE_ARN=$EXEC_ROLE_ARN"
log "  TASK_ROLE_ARN=$TASK_ROLE_ARN"
log "  CODEBUILD_ROLE_ARN=$CODEBUILD_ROLE_ARN"
