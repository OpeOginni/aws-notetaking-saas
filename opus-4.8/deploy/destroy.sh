#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# destroy.sh
# Tears down all AWS resources created by the deploy scripts. Best-effort:
# continues past individual failures. Use with care.
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

warn "Destroying all ${PROJECT} resources in ${AWS_REGION}..."
read -p "Type 'destroy' to confirm: " confirm
[ "$confirm" = "destroy" ] || { log "Aborted."; exit 0; }

R() { "$@" 2>/dev/null || true; }

# Service + cluster
R aws ecs update-service --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" \
  --region "$AWS_REGION" --desired-count 0
R aws ecs delete-service --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" \
  --region "$AWS_REGION" --force
R aws ecs delete-cluster --cluster "$CLUSTER_NAME" --region "$AWS_REGION"

# ALB + target group
ALB_ARN=$(state_get alb_arn)
[ -n "$ALB_ARN" ] && {
  LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --region "$AWS_REGION" --query 'Listeners[].ListenerArn' --output text 2>/dev/null || echo "")
  for l in $LISTENERS; do R aws elbv2 delete-listener --listener-arn "$l" --region "$AWS_REGION"; done
  R aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" --region "$AWS_REGION"
}
TG_ARN=$(state_get tg_arn)
[ -n "$TG_ARN" ] && { sleep 10; R aws elbv2 delete-target-group --target-group-arn "$TG_ARN" --region "$AWS_REGION"; }

# RDS
R aws rds delete-db-instance --db-instance-identifier "$DB_INSTANCE_ID" \
  --region "$AWS_REGION" --skip-final-snapshot --delete-automated-backups
log "Waiting for RDS deletion..."
R aws rds wait db-instance-deleted --db-instance-identifier "$DB_INSTANCE_ID" --region "$AWS_REGION"
R aws rds delete-db-subnet-group --db-subnet-group-name "${PROJECT}-db-subnets" --region "$AWS_REGION"

# Secrets
R aws secretsmanager delete-secret --secret-id "${PROJECT}-db-credentials" --region "$AWS_REGION" --force-delete-without-recovery

# S3 buckets
BUCKET=$(state_get s3_bucket)
[ -n "$BUCKET" ] && { R aws s3 rm "s3://${BUCKET}" --recursive; R aws s3api delete-bucket --bucket "$BUCKET" --region "$AWS_REGION"; }
R aws s3 rm "s3://${PROJECT}-build-${ACCOUNT_ID}" --recursive
R aws s3api delete-bucket --bucket "${PROJECT}-build-${ACCOUNT_ID}" --region "$AWS_REGION"

# CodeBuild + ECR
R aws codebuild delete-project --name "$CODEBUILD_PROJECT" --region "$AWS_REGION"
R aws ecr delete-repository --repository-name "$ECR_REPO" --region "$AWS_REGION" --force

# CloudWatch logs
R aws logs delete-log-group --log-group-name "$LOG_GROUP" --region "$AWS_REGION"

# Security groups (may need a moment after dependent resources go away)
sleep 20
for sg in "$(state_get ecs_sg)" "$(state_get rds_sg)" "$(state_get alb_sg)"; do
  [ -n "$sg" ] && R aws ec2 delete-security-group --group-id "$sg" --region "$AWS_REGION"
done

# IAM roles (detach/delete inline + managed policies first)
for role in "$EXEC_ROLE_NAME" "$TASK_ROLE_NAME" "$CODEBUILD_ROLE_NAME"; do
  for p in $(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
    R aws iam detach-role-policy --role-name "$role" --policy-arn "$p"
  done
  for p in $(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text 2>/dev/null); do
    R aws iam delete-role-policy --role-name "$role" --policy-name "$p"
  done
  R aws iam delete-role --role-name "$role"
done

rm -rf "$STATE_DIR"
log "Teardown complete."
