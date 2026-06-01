#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# deploy-all.sh
# One-command, end-to-end deployment of NoteSaaS to AWS.
# Runs every step in order. Safe to re-run (each step is idempotent).
#
# Usage:
#   ./deploy/deploy-all.sh
#
# Prereqs: AWS CLI v2 configured with credentials, `zip` available.
# ----------------------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

log "=============================================="
log " Deploying ${PROJECT} to AWS (${AWS_REGION})"
log " Account: ${ACCOUNT_ID}"
log "=============================================="

bash "${SCRIPT_DIR}/01-network.sh"
bash "${SCRIPT_DIR}/03-s3.sh"          # bucket first so IAM can scope to it
bash "${SCRIPT_DIR}/02-iam.sh"
bash "${SCRIPT_DIR}/04-rds.sh"
bash "${SCRIPT_DIR}/05-build-image.sh"
bash "${SCRIPT_DIR}/06-ecs.sh"
bash "${SCRIPT_DIR}/07-verify.sh"

log "=============================================="
log " Deployment complete!"
log " URL: http://$(state_get alb_dns)"
log "=============================================="
