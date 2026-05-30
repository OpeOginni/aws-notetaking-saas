#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# 01-network.sh
# Discovers the default VPC + public subnets and creates the security groups
# used by the ALB, the ECS tasks, and the RDS instance.
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

log "Discovering default VPC..."
VPC_ID=$(aws ec2 describe-vpcs --region "$AWS_REGION" \
  --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' --output text)
if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
  err "No default VPC found in $AWS_REGION. Set VPC_ID/subnets manually."
  exit 1
fi
state_set vpc_id "$VPC_ID"
log "Using VPC: $VPC_ID"

# Collect subnets (we use the default public subnets for both ALB and tasks).
SUBNET_IDS=$(aws ec2 describe-subnets --region "$AWS_REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --query 'Subnets[].SubnetId' --output text | tr '\t' ',')
state_set subnet_ids "$SUBNET_IDS"
log "Using subnets: $SUBNET_IDS"

# --- Security group helper --------------------------------------------------
ensure_sg() {
  local name="$1"; local desc="$2"
  local sg
  sg=$(aws ec2 describe-security-groups --region "$AWS_REGION" \
    --filters Name=group-name,Values="$name" Name=vpc-id,Values="$VPC_ID" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")
  if [ "$sg" = "None" ] || [ -z "$sg" ]; then
    sg=$(aws ec2 create-security-group --region "$AWS_REGION" \
      --group-name "$name" --description "$desc" --vpc-id "$VPC_ID" \
      --query 'GroupId' --output text)
    log "Created security group $name => $sg"
  else
    log "Security group $name already exists => $sg"
  fi
  echo "$sg"
}

ALB_SG=$(ensure_sg "${PROJECT}-alb-sg" "ALB ingress for ${PROJECT}")
ECS_SG=$(ensure_sg "${PROJECT}-ecs-sg" "ECS tasks for ${PROJECT}")
RDS_SG=$(ensure_sg "${PROJECT}-rds-sg" "RDS for ${PROJECT}")
state_set alb_sg "$ALB_SG"
state_set ecs_sg "$ECS_SG"
state_set rds_sg "$RDS_SG"

# --- Ingress rules (ignore "already exists" errors) -------------------------
auth() { aws ec2 authorize-security-group-ingress --region "$AWS_REGION" "$@" >/dev/null 2>&1 || true; }

# ALB: allow HTTP from the internet.
auth --group-id "$ALB_SG" --protocol tcp --port 80 --cidr 0.0.0.0/0

# ECS tasks: allow app port only from the ALB SG.
auth --group-id "$ECS_SG" --protocol tcp --port "$APP_PORT" \
  --source-group "$ALB_SG"

# RDS: allow Postgres only from the ECS task SG.
auth --group-id "$RDS_SG" --protocol tcp --port 5432 \
  --source-group "$ECS_SG"

log "Network setup complete."
log "  VPC_ID=$VPC_ID"
log "  ALB_SG=$ALB_SG  ECS_SG=$ECS_SG  RDS_SG=$RDS_SG"
