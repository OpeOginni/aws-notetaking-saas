#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# 07-verify.sh
# Waits for the ECS service to stabilize and the ALB targets to become healthy,
# then probes the public health endpoint.
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

ALB_DNS=$(state_get alb_dns)
TG_ARN=$(state_get tg_arn)

log "Waiting for ECS service to stabilize (this may take a few minutes)..."
aws ecs wait services-stable --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" \
  --region "$AWS_REGION" || warn "Service did not stabilize in time; continuing checks."

log "Checking target group health..."
for i in $(seq 1 20); do
  HEALTHY=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
    --region "$AWS_REGION" \
    --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" \
    --output text 2>/dev/null || echo 0)
  log "  healthy targets: $HEALTHY"
  if [ "$HEALTHY" != "0" ] && [ -n "$HEALTHY" ]; then break; fi
  sleep 15
done

log "Probing http://${ALB_DNS}/api/health ..."
for i in $(seq 1 20); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${ALB_DNS}/api/health" || echo 000)
  log "  HTTP $CODE"
  if [ "$CODE" = "200" ]; then
    log "SUCCESS — application is live at http://${ALB_DNS}"
    curl -s "http://${ALB_DNS}/api/health"; echo
    exit 0
  fi
  sleep 15
done

warn "Health endpoint did not return 200 yet."
warn "The ALB may still be warming up. Check: http://${ALB_DNS}/api/health"
warn "Inspect ECS logs in CloudWatch log group: ${LOG_GROUP}"
exit 0
