#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-gpt55-notes}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
STACK_NAME="${STACK_NAME:-$APP_NAME-base}"
DB_NAME="${DB_NAME:-notes_saas}"
DB_USERNAME="${DB_USERNAME:-notes_admin}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_FILE="$ROOT_DIR/deployment-outputs.env"

if [[ -z "${DB_PASSWORD:-}" && -f "$OUTPUT_FILE" ]]; then
  DB_PASSWORD="$(grep '^DB_PASSWORD=' "$OUTPUT_FILE" | cut -d= -f2-)"
fi

DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)}"

aws cloudformation deploy \
  --region "$AWS_REGION" \
  --stack-name "$STACK_NAME" \
  --template-file "$ROOT_DIR/infra/cloudformation/base.yml" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    AppName="$APP_NAME" \
    DbName="$DB_NAME" \
    DbUsername="$DB_USERNAME" \
    DbPassword="$DB_PASSWORD"

outputs_json="$(aws cloudformation describe-stacks --region "$AWS_REGION" --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs' --output json)"
get_output() {
  node -e "const outputs=$outputs_json; const key=process.argv[1]; const row=outputs.find(o=>o.OutputKey===key); if (!row) process.exit(1); process.stdout.write(row.OutputValue);" "$1"
}

db_endpoint="$(get_output DatabaseEndpoint)"
db_name="$(get_output DatabaseName)"
db_user="$(get_output DatabaseUsername)"

cat > "$OUTPUT_FILE" <<EOF
APP_NAME=$APP_NAME
AWS_REGION=$AWS_REGION
STACK_NAME=$STACK_NAME
DB_PASSWORD=$DB_PASSWORD
DATABASE_URL=postgres://$db_user:$DB_PASSWORD@$db_endpoint:5432/$db_name
DB_SSL=true
S3_BUCKET_NAME=$(get_output UploadsBucketName)
COOKIE_SECURE=${COOKIE_SECURE:-false}
ECR_REPOSITORY_URI=$(get_output EcrRepositoryUri)
ECS_CLUSTER=$(get_output ClusterName)
ECS_SERVICE=$APP_NAME-service
EXECUTION_ROLE_ARN=$(get_output ExecutionRoleArn)
TASK_ROLE_ARN=$(get_output TaskRoleArn)
LOG_GROUP_NAME=$(get_output LogGroupName)
TARGET_GROUP_ARN=$(get_output TargetGroupArn)
LISTENER_ARN=$(get_output ListenerArn)
PUBLIC_SUBNETS=$(get_output PublicSubnets)
APP_SECURITY_GROUP_ID=$(get_output AppSecurityGroupId)
LOAD_BALANCER_DNS=$(get_output LoadBalancerDnsName)
PUBLIC_URL=http://$(get_output LoadBalancerDnsName)
APP_URL=http://$(get_output LoadBalancerDnsName)
EOF

chmod 600 "$OUTPUT_FILE"
echo "Infrastructure deployed. Outputs written to $OUTPUT_FILE"
echo "Public URL after app deployment: http://$(get_output LoadBalancerDnsName)"
