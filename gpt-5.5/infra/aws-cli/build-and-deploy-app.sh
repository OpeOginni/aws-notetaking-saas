#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_FILE="${OUTPUT_FILE:-$ROOT_DIR/deployment-outputs.env}"

if [[ ! -f "$OUTPUT_FILE" ]]; then
  echo "Missing $OUTPUT_FILE. Run infra/aws-cli/deploy-infra.sh first." >&2
  exit 1
fi

set -a
source "$OUTPUT_FILE"
set +a

IMAGE_TAG="${IMAGE_TAG:-$(date +%Y%m%d%H%M%S)}"
IMAGE_URI="$ECR_REPOSITORY_URI:$IMAGE_TAG"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

if command -v docker >/dev/null 2>&1; then
  aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
  docker build --platform linux/amd64 -t "$IMAGE_URI" "$ROOT_DIR"
  docker push "$IMAGE_URI"
else
  echo "Docker CLI not found locally; using AWS CodeBuild for the image build."
  CODEBUILD_ROLE_NAME="$APP_NAME-codebuild-role"
  CODEBUILD_PROJECT_NAME="$APP_NAME-image-build"
  SOURCE_KEY="codebuild-source/$IMAGE_TAG.zip"
  SOURCE_ZIP="$(mktemp --suffix=.zip)"
  TRUST_POLICY="$(mktemp)"
  BUILD_POLICY="$(mktemp)"

  rm -f "$SOURCE_ZIP"
  (cd "$ROOT_DIR" && zip -qr "$SOURCE_ZIP" . -x "node_modules/*" ".next/*" ".git/*" "deployment-outputs.env" "*.zip")
  aws s3 cp "$SOURCE_ZIP" "s3://$S3_BUCKET_NAME/$SOURCE_KEY" --region "$AWS_REGION" >/dev/null
  rm -f "$SOURCE_ZIP"

  cat > "$TRUST_POLICY" <<EOF_TRUST
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "codebuild.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF_TRUST

  if ! aws iam get-role --role-name "$CODEBUILD_ROLE_NAME" >/dev/null 2>&1; then
    aws iam create-role --role-name "$CODEBUILD_ROLE_NAME" --assume-role-policy-document "file://$TRUST_POLICY" >/dev/null
  fi

  cat > "$BUILD_POLICY" <<EOF_POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], "Resource": "*" },
    { "Effect": "Allow", "Action": ["ecr:GetAuthorizationToken"], "Resource": "*" },
    { "Effect": "Allow", "Action": ["ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"], "Resource": "arn:aws:ecr:$AWS_REGION:$ACCOUNT_ID:repository/$APP_NAME-app" },
    { "Effect": "Allow", "Action": ["s3:GetObject", "s3:GetObjectVersion"], "Resource": "arn:aws:s3:::$S3_BUCKET_NAME/*" }
  ]
}
EOF_POLICY

  aws iam put-role-policy --role-name "$CODEBUILD_ROLE_NAME" --policy-name "$APP_NAME-codebuild-policy" --policy-document "file://$BUILD_POLICY" >/dev/null
  rm -f "$TRUST_POLICY" "$BUILD_POLICY"
  sleep 10

  CODEBUILD_ROLE_ARN="$(aws iam get-role --role-name "$CODEBUILD_ROLE_NAME" --query 'Role.Arn' --output text)"
  if aws codebuild batch-get-projects --region "$AWS_REGION" --names "$CODEBUILD_PROJECT_NAME" --query 'projects[0].name' --output text 2>/dev/null | grep -q "$CODEBUILD_PROJECT_NAME"; then
    aws codebuild update-project \
      --region "$AWS_REGION" \
      --name "$CODEBUILD_PROJECT_NAME" \
      --source "type=S3,location=$S3_BUCKET_NAME/$SOURCE_KEY" \
      --artifacts type=NO_ARTIFACTS \
      --environment "type=LINUX_CONTAINER,image=aws/codebuild/standard:7.0,computeType=BUILD_GENERAL1_MEDIUM,privilegedMode=true" \
      --service-role "$CODEBUILD_ROLE_ARN" >/dev/null
  else
    aws codebuild create-project \
      --region "$AWS_REGION" \
      --name "$CODEBUILD_PROJECT_NAME" \
      --source "type=S3,location=$S3_BUCKET_NAME/$SOURCE_KEY" \
      --artifacts type=NO_ARTIFACTS \
      --environment "type=LINUX_CONTAINER,image=aws/codebuild/standard:7.0,computeType=BUILD_GENERAL1_MEDIUM,privilegedMode=true" \
      --service-role "$CODEBUILD_ROLE_ARN" >/dev/null
  fi

  BUILD_ID="$(aws codebuild start-build \
    --region "$AWS_REGION" \
    --project-name "$CODEBUILD_PROJECT_NAME" \
    --source-location-override "$S3_BUCKET_NAME/$SOURCE_KEY" \
    --environment-variables-override \
      name=AWS_REGION,value="$AWS_REGION",type=PLAINTEXT \
      name=ACCOUNT_ID,value="$ACCOUNT_ID",type=PLAINTEXT \
      name=IMAGE_URI,value="$IMAGE_URI",type=PLAINTEXT \
    --query 'build.id' --output text)"

  while true; do
    BUILD_STATUS="$(aws codebuild batch-get-builds --region "$AWS_REGION" --ids "$BUILD_ID" --query 'builds[0].buildStatus' --output text)"
    echo "CodeBuild status: $BUILD_STATUS"
    case "$BUILD_STATUS" in
      SUCCEEDED) break ;;
      FAILED|FAULT|STOPPED|TIMED_OUT)
        aws codebuild batch-get-builds --region "$AWS_REGION" --ids "$BUILD_ID" --query 'builds[0].logs.deepLink' --output text
        exit 1
        ;;
    esac
    sleep 20
  done
fi

task_def_json="$(mktemp)"
cat > "$task_def_json" <<EOF
{
  "family": "$APP_NAME-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "$EXECUTION_ROLE_ARN",
  "taskRoleArn": "$TASK_ROLE_ARN",
  "containerDefinitions": [
    {
      "name": "$APP_NAME-web",
      "image": "$IMAGE_URI",
      "essential": true,
      "portMappings": [{ "containerPort": 3000, "protocol": "tcp" }],
      "environment": [
        { "name": "DATABASE_URL", "value": "$DATABASE_URL" },
        { "name": "DB_SSL", "value": "$DB_SSL" },
        { "name": "S3_BUCKET_NAME", "value": "$S3_BUCKET_NAME" },
        { "name": "COOKIE_SECURE", "value": "${COOKIE_SECURE:-false}" },
        { "name": "APP_URL", "value": "$PUBLIC_URL" },
        { "name": "AWS_REGION", "value": "$AWS_REGION" },
        { "name": "NODE_ENV", "value": "production" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "$LOG_GROUP_NAME",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "web"
        }
      }
    }
  ]
}
EOF

TASK_DEFINITION_ARN="$(aws ecs register-task-definition --region "$AWS_REGION" --cli-input-json "file://$task_def_json" --query 'taskDefinition.taskDefinitionArn' --output text)"
rm -f "$task_def_json"

if aws ecs describe-services --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --query 'services[0].status' --output text 2>/dev/null | grep -qE 'ACTIVE|DRAINING'; then
  aws ecs update-service --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --task-definition "$TASK_DEFINITION_ARN" --desired-count 1 >/dev/null
else
  aws ecs create-service \
    --region "$AWS_REGION" \
    --cluster "$ECS_CLUSTER" \
    --service-name "$ECS_SERVICE" \
    --task-definition "$TASK_DEFINITION_ARN" \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$PUBLIC_SUBNETS],securityGroups=[$APP_SECURITY_GROUP_ID],assignPublicIp=ENABLED}" \
    --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=$APP_NAME-web,containerPort=3000" >/dev/null

  aws elbv2 modify-listener \
    --region "$AWS_REGION" \
    --listener-arn "$LISTENER_ARN" \
    --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" >/dev/null
fi

aws ecs wait services-stable --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"
echo "Application deployed: $PUBLIC_URL"
