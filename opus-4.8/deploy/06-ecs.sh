#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# 06-ecs.sh
# Creates the ALB + target group + listener, registers the ECS task definition,
# and creates/updates the Fargate service. Idempotent.
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

VPC_ID=$(state_get vpc_id)
SUBNET_IDS=$(state_get subnet_ids)
ALB_SG=$(state_get alb_sg)
ECS_SG=$(state_get ecs_sg)
EXEC_ROLE_ARN=$(state_get exec_role_arn)
TASK_ROLE_ARN=$(state_get task_role_arn)
DB_SECRET_ARN=$(state_get db_secret_arn)
DATABASE_URL=$(state_get database_url)
S3_BUCKET=$(state_get s3_bucket)
IMAGE_URI=$(state_get image_uri)

for v in VPC_ID SUBNET_IDS ALB_SG ECS_SG EXEC_ROLE_ARN TASK_ROLE_ARN DATABASE_URL S3_BUCKET IMAGE_URI; do
  if [ -z "${!v}" ]; then err "Missing state: $v. Run prior steps first."; exit 1; fi
done

SUBNET_ARGS=$(echo "$SUBNET_IDS" | tr ',' ' ')

# --- AUTH_SECRET (stable across re-runs) ------------------------------------
AUTH_SECRET=$(state_get auth_secret)
if [ -z "$AUTH_SECRET" ]; then
  AUTH_SECRET=$(aws secretsmanager get-random-password --region "$AWS_REGION" \
    --password-length 48 --exclude-punctuation --query RandomPassword --output text)
  state_set auth_secret "$AUTH_SECRET"
fi

# --- Log group --------------------------------------------------------------
aws logs create-log-group --log-group-name "$LOG_GROUP" --region "$AWS_REGION" >/dev/null 2>&1 || true

# --- ECS cluster ------------------------------------------------------------
aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" \
  --capacity-providers FARGATE >/dev/null 2>&1 || true
log "ECS cluster ready: $CLUSTER_NAME"

# --- ALB --------------------------------------------------------------------
ALB_ARN=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" --region "$AWS_REGION" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || echo "None")
if [ "$ALB_ARN" = "None" ] || [ -z "$ALB_ARN" ]; then
  log "Creating ALB $ALB_NAME..."
  ALB_ARN=$(aws elbv2 create-load-balancer --name "$ALB_NAME" --region "$AWS_REGION" \
    --type application --scheme internet-facing \
    --subnets $SUBNET_ARGS --security-groups "$ALB_SG" \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text)
fi
state_set alb_arn "$ALB_ARN"
ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" \
  --region "$AWS_REGION" --query 'LoadBalancers[0].DNSName' --output text)
state_set alb_dns "$ALB_DNS"
log "ALB DNS: $ALB_DNS"

# --- Target group -----------------------------------------------------------
TG_ARN=$(aws elbv2 describe-target-groups --names "$TG_NAME" --region "$AWS_REGION" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "None")
if [ "$TG_ARN" = "None" ] || [ -z "$TG_ARN" ]; then
  log "Creating target group $TG_NAME..."
  TG_ARN=$(aws elbv2 create-target-group --name "$TG_NAME" --region "$AWS_REGION" \
    --protocol HTTP --port "$APP_PORT" --vpc-id "$VPC_ID" \
    --target-type ip \
    --health-check-path "/api/health" \
    --health-check-interval-seconds 30 \
    --healthy-threshold-count 2 --unhealthy-threshold-count 3 \
    --query 'TargetGroups[0].TargetGroupArn' --output text)
fi
state_set tg_arn "$TG_ARN"

# --- Listener ---------------------------------------------------------------
LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" \
  --region "$AWS_REGION" --query 'Listeners[?Port==`80`].ListenerArn | [0]' --output text 2>/dev/null || echo "None")
if [ "$LISTENER_ARN" = "None" ] || [ -z "$LISTENER_ARN" ]; then
  log "Creating HTTP listener..."
  aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" --region "$AWS_REGION" \
    --protocol HTTP --port 80 \
    --default-actions Type=forward,TargetGroupArn="$TG_ARN" >/dev/null
fi

# --- Task definition --------------------------------------------------------
log "Registering task definition..."
CONTAINER_DEF=$(cat <<JSON
[
  {
    "name": "${PROJECT}",
    "image": "${IMAGE_URI}",
    "essential": true,
    "portMappings": [{"containerPort": ${APP_PORT}, "protocol": "tcp"}],
    "environment": [
      {"name": "NODE_ENV", "value": "production"},
      {"name": "PORT", "value": "${APP_PORT}"},
      {"name": "HOSTNAME", "value": "0.0.0.0"},
      {"name": "COOKIE_SECURE", "value": "${COOKIE_SECURE:-false}"},
      {"name": "AWS_REGION", "value": "${AWS_REGION}"},
      {"name": "S3_BUCKET", "value": "${S3_BUCKET}"},
      {"name": "AUTH_SECRET", "value": "${AUTH_SECRET}"},
      {"name": "DATABASE_URL", "value": "${DATABASE_URL}"}
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${LOG_GROUP}",
        "awslogs-region": "${AWS_REGION}",
        "awslogs-stream-prefix": "ecs"
      }
    }
  }
]
JSON
)

TASK_DEF_ARN=$(aws ecs register-task-definition --region "$AWS_REGION" \
  --family "$TASK_FAMILY" \
  --requires-compatibilities FARGATE \
  --network-mode awsvpc \
  --cpu "$TASK_CPU" --memory "$TASK_MEMORY" \
  --execution-role-arn "$EXEC_ROLE_ARN" \
  --task-role-arn "$TASK_ROLE_ARN" \
  --runtime-platform '{"cpuArchitecture":"X86_64","operatingSystemFamily":"LINUX"}' \
  --container-definitions "$CONTAINER_DEF" \
  --query 'taskDefinition.taskDefinitionArn' --output text)
state_set task_def_arn "$TASK_DEF_ARN"
log "Task definition: $TASK_DEF_ARN"

# --- Service ----------------------------------------------------------------
NET_CONFIG="awsvpcConfiguration={subnets=[$(echo "$SUBNET_IDS")],securityGroups=[${ECS_SG}],assignPublicIp=ENABLED}"

SVC_STATUS=$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" \
  --region "$AWS_REGION" --query 'services[0].status' --output text 2>/dev/null || echo "MISSING")

if [ "$SVC_STATUS" = "ACTIVE" ]; then
  log "Updating existing service $SERVICE_NAME..."
  aws ecs update-service --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" \
    --region "$AWS_REGION" --task-definition "$TASK_DEF_ARN" \
    --desired-count "$DESIRED_COUNT" --force-new-deployment >/dev/null
else
  log "Creating service $SERVICE_NAME..."
  aws ecs create-service --cluster "$CLUSTER_NAME" --service-name "$SERVICE_NAME" \
    --region "$AWS_REGION" --task-definition "$TASK_DEF_ARN" \
    --desired-count "$DESIRED_COUNT" --launch-type FARGATE \
    --network-configuration "$NET_CONFIG" \
    --load-balancers "targetGroupArn=${TG_ARN},containerName=${PROJECT},containerPort=${APP_PORT}" \
    --health-check-grace-period-seconds 120 >/dev/null
fi

log "ECS service deploying. App will be available at:"
log "  http://${ALB_DNS}"
