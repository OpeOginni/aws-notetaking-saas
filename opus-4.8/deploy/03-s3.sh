#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# 03-s3.sh
# Creates the private S3 bucket used for note attachments and locks down all
# public access. Files are served through the app (presigned/proxied), never
# directly from the bucket.
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

BUCKET="${S3_BUCKET_PREFIX}-${ACCOUNT_ID}"
state_set s3_bucket "$BUCKET"

if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  log "S3 bucket $BUCKET already exists"
else
  log "Creating S3 bucket $BUCKET..."
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$AWS_REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$AWS_REGION" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION" >/dev/null
  fi
fi

# Block all public access.
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null

# Default server-side encryption.
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' >/dev/null

# CORS so the app (served via ALB) can fetch objects through its own routes.
aws s3api put-bucket-cors --bucket "$BUCKET" --cors-configuration '{
  "CORSRules":[{
    "AllowedHeaders":["*"],
    "AllowedMethods":["GET","PUT","POST","DELETE"],
    "AllowedOrigins":["*"],
    "ExposeHeaders":["ETag"],
    "MaxAgeSeconds":3000
  }]
}' >/dev/null

log "S3 bucket ready: $BUCKET (private, encrypted)"
