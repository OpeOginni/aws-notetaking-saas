#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# 05-build-image.sh
# Builds the Docker image WITHOUT a local Docker daemon by using AWS CodeBuild:
#   1. Ensures the ECR repository exists.
#   2. Zips the application source and uploads it to an S3 build bucket.
#   3. Ensures a CodeBuild project (privileged Docker build) exists.
#   4. Starts a build that builds the image and pushes it to ECR.
#   5. Waits for the build to finish.
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"

CODEBUILD_ROLE_ARN=$(state_get codebuild_role_arn)
if [ -z "$CODEBUILD_ROLE_ARN" ]; then
  err "CodeBuild role missing. Run 02-iam.sh first."
  exit 1
fi

# --- 1. ECR repo ------------------------------------------------------------
if aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1; then
  log "ECR repo $ECR_REPO already exists"
else
  aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION" \
    --image-scanning-configuration scanOnPush=false >/dev/null
  log "Created ECR repo $ECR_REPO"
fi

# --- 2. Build source bucket + zip upload ------------------------------------
BUILD_BUCKET="${PROJECT}-build-${ACCOUNT_ID}"
if ! aws s3api head-bucket --bucket "$BUILD_BUCKET" >/dev/null 2>&1; then
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUILD_BUCKET" --region "$AWS_REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUILD_BUCKET" --region "$AWS_REGION" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION" >/dev/null
  fi
  aws s3api put-public-access-block --bucket "$BUILD_BUCKET" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null
  log "Created build bucket $BUILD_BUCKET"
fi

log "Packaging source..."
ZIP_PATH="${STATE_DIR}/source.zip"
rm -f "$ZIP_PATH"
( cd "$APP_DIR" && zip -qr "$ZIP_PATH" . \
    -x "node_modules/*" ".next/*" ".git/*" "deploy/.state/*" "*.log" )
aws s3 cp "$ZIP_PATH" "s3://${BUILD_BUCKET}/source.zip" --region "$AWS_REGION" >/dev/null
log "Uploaded source to s3://${BUILD_BUCKET}/source.zip"

# --- 3. CodeBuild project ---------------------------------------------------
ENV_JSON=$(cat <<JSON
{
  "type": "LINUX_CONTAINER",
  "image": "aws/codebuild/amazonlinux2-x86_64-standard:5.0",
  "computeType": "BUILD_GENERAL1_SMALL",
  "privilegedMode": true,
  "environmentVariables": [
    {"name": "AWS_DEFAULT_REGION", "value": "${AWS_REGION}"},
    {"name": "AWS_ACCOUNT_ID", "value": "${ACCOUNT_ID}"},
    {"name": "ECR_REPO", "value": "${ECR_REPO}"},
    {"name": "IMAGE_TAG", "value": "${IMAGE_TAG}"}
  ]
}
JSON
)
SOURCE_JSON=$(cat <<JSON
{
  "type": "S3",
  "location": "${BUILD_BUCKET}/source.zip",
  "buildspec": "deploy/buildspec.yml"
}
JSON
)

if aws codebuild batch-get-projects --names "$CODEBUILD_PROJECT" --region "$AWS_REGION" \
    --query 'projects[0].name' --output text 2>/dev/null | grep -q "$CODEBUILD_PROJECT"; then
  log "Updating CodeBuild project $CODEBUILD_PROJECT"
  aws codebuild update-project --name "$CODEBUILD_PROJECT" --region "$AWS_REGION" \
    --source "$SOURCE_JSON" --artifacts '{"type":"NO_ARTIFACTS"}' \
    --environment "$ENV_JSON" --service-role "$CODEBUILD_ROLE_ARN" >/dev/null
else
  log "Creating CodeBuild project $CODEBUILD_PROJECT"
  aws codebuild create-project --name "$CODEBUILD_PROJECT" --region "$AWS_REGION" \
    --source "$SOURCE_JSON" --artifacts '{"type":"NO_ARTIFACTS"}' \
    --environment "$ENV_JSON" --service-role "$CODEBUILD_ROLE_ARN" >/dev/null
fi

# --- 4. Start build ---------------------------------------------------------
log "Starting CodeBuild image build..."
BUILD_ID=$(aws codebuild start-build --project-name "$CODEBUILD_PROJECT" \
  --region "$AWS_REGION" --query 'build.id' --output text)
log "Build started: $BUILD_ID"

# --- 5. Wait for completion -------------------------------------------------
while true; do
  STATUS=$(aws codebuild batch-get-builds --ids "$BUILD_ID" --region "$AWS_REGION" \
    --query 'builds[0].buildStatus' --output text)
  PHASE=$(aws codebuild batch-get-builds --ids "$BUILD_ID" --region "$AWS_REGION" \
    --query 'builds[0].currentPhase' --output text)
  log "  build status=$STATUS phase=$PHASE"
  case "$STATUS" in
    SUCCEEDED) log "Image build succeeded."; break ;;
    FAILED|FAULT|STOPPED|TIMED_OUT)
      err "Image build failed with status $STATUS"
      err "Inspect logs: aws codebuild batch-get-builds --ids $BUILD_ID --region $AWS_REGION"
      exit 1 ;;
  esac
  sleep 15
done

state_set image_uri "${ECR_URI}:${IMAGE_TAG}"
log "Image pushed: ${ECR_URI}:${IMAGE_TAG}"
