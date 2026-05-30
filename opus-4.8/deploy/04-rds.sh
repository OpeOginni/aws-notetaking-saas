#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# 04-rds.sh
# Provisions a PostgreSQL RDS instance, stores the generated credentials in
# Secrets Manager, and writes the connection string to the state dir.
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

RDS_SG=$(state_get rds_sg)
SUBNET_IDS=$(state_get subnet_ids)
if [ -z "$RDS_SG" ] || [ -z "$SUBNET_IDS" ]; then
  err "Network state missing. Run 01-network.sh first."
  exit 1
fi

# --- DB subnet group --------------------------------------------------------
SUBNET_GROUP="${PROJECT}-db-subnets"
SUBNET_ARGS=$(echo "$SUBNET_IDS" | tr ',' ' ')
if aws rds describe-db-subnet-groups --db-subnet-group-name "$SUBNET_GROUP" --region "$AWS_REGION" >/dev/null 2>&1; then
  log "DB subnet group $SUBNET_GROUP already exists"
else
  aws rds create-db-subnet-group --region "$AWS_REGION" \
    --db-subnet-group-name "$SUBNET_GROUP" \
    --db-subnet-group-description "${PROJECT} db subnets" \
    --subnet-ids $SUBNET_ARGS >/dev/null
  log "Created DB subnet group $SUBNET_GROUP"
fi

# --- Password / secret ------------------------------------------------------
SECRET_NAME="${PROJECT}-db-credentials"
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  log "Using existing DB secret $SECRET_NAME"
  DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" \
    --region "$AWS_REGION" --query SecretString --output text | sed -n 's/.*"password":"\([^"]*\)".*/\1/p')
else
  DB_PASSWORD=$(aws secretsmanager get-random-password --region "$AWS_REGION" \
    --password-length 28 --exclude-punctuation --require-each-included-type \
    --query RandomPassword --output text)
fi

# --- Create / reuse the instance --------------------------------------------
if aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_ID" --region "$AWS_REGION" >/dev/null 2>&1; then
  log "RDS instance $DB_INSTANCE_ID already exists"
else
  log "Creating RDS PostgreSQL instance $DB_INSTANCE_ID (this can take several minutes)..."
  aws rds create-db-instance --region "$AWS_REGION" \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --db-instance-class "$DB_INSTANCE_CLASS" \
    --engine postgres \
    --engine-version "$DB_ENGINE_VERSION" \
    --allocated-storage "$DB_ALLOCATED_STORAGE" \
    --master-username "$DB_USER" \
    --master-user-password "$DB_PASSWORD" \
    --db-name "$DB_NAME" \
    --vpc-security-group-ids "$RDS_SG" \
    --db-subnet-group-name "$SUBNET_GROUP" \
    --no-multi-az \
    --publicly-accessible \
    --backup-retention-period 1 \
    --storage-type gp3 >/dev/null
fi

log "Waiting for RDS instance to become available..."
aws rds wait db-instance-available --db-instance-identifier "$DB_INSTANCE_ID" --region "$AWS_REGION"

ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_ID" \
  --region "$AWS_REGION" --query 'DBInstances[0].Endpoint.Address' --output text)
state_set db_endpoint "$ENDPOINT"

DATABASE_URL="postgres://${DB_USER}:${DB_PASSWORD}@${ENDPOINT}:5432/${DB_NAME}"
state_set database_url "$DATABASE_URL"

# Store/refresh the secret (used by the ECS task definition).
SECRET_JSON="{\"username\":\"${DB_USER}\",\"password\":\"${DB_PASSWORD}\",\"host\":\"${ENDPOINT}\",\"port\":5432,\"dbname\":\"${DB_NAME}\",\"DATABASE_URL\":\"${DATABASE_URL}\"}"
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws secretsmanager put-secret-value --secret-id "$SECRET_NAME" \
    --region "$AWS_REGION" --secret-string "$SECRET_JSON" >/dev/null
else
  aws secretsmanager create-secret --name "$SECRET_NAME" \
    --region "$AWS_REGION" --secret-string "$SECRET_JSON" >/dev/null
fi
DB_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id "$SECRET_NAME" \
  --region "$AWS_REGION" --query 'ARN' --output text)
state_set db_secret_arn "$DB_SECRET_ARN"

log "RDS ready at $ENDPOINT"
log "DB secret: $SECRET_NAME"
