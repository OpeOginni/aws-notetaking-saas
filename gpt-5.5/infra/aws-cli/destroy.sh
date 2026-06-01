#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_FILE="${OUTPUT_FILE:-$ROOT_DIR/deployment-outputs.env}"

if [[ -f "$OUTPUT_FILE" ]]; then
  set -a
  source "$OUTPUT_FILE"
  set +a
fi

APP_NAME="${APP_NAME:-gpt55-notes}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
STACK_NAME="${STACK_NAME:-$APP_NAME-base}"

if [[ -n "${ECS_CLUSTER:-}" && -n "${ECS_SERVICE:-}" ]]; then
  aws ecs update-service --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --desired-count 0 >/dev/null 2>&1 || true
  aws ecs delete-service --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --force >/dev/null 2>&1 || true
fi

if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
  aws s3 rm "s3://$S3_BUCKET_NAME" --recursive --region "$AWS_REGION" >/dev/null 2>&1 || true
fi

aws codebuild delete-project --region "$AWS_REGION" --name "$APP_NAME-image-build" >/dev/null 2>&1 || true
aws iam delete-role-policy --role-name "$APP_NAME-codebuild-role" --policy-name "$APP_NAME-codebuild-policy" >/dev/null 2>&1 || true
aws iam delete-role --role-name "$APP_NAME-codebuild-role" >/dev/null 2>&1 || true

image_ids="$(aws ecr list-images --region "$AWS_REGION" --repository-name "$APP_NAME-app" --query 'imageIds' --output json 2>/dev/null || true)"
if [[ -n "$image_ids" && "$image_ids" != "[]" ]]; then
  delete_images_json="$(mktemp)"
  cat > "$delete_images_json" <<EOF_IMAGES
{ "repositoryName": "$APP_NAME-app", "imageIds": $image_ids }
EOF_IMAGES
  aws ecr batch-delete-image --region "$AWS_REGION" --cli-input-json "file://$delete_images_json" >/dev/null 2>&1 || true
  rm -f "$delete_images_json"
fi

aws cloudformation delete-stack --region "$AWS_REGION" --stack-name "$STACK_NAME"
aws cloudformation wait stack-delete-complete --region "$AWS_REGION" --stack-name "$STACK_NAME"
echo "Deleted stack $STACK_NAME"
