#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_FILE="${OUTPUT_FILE:-$ROOT_DIR/deployment-outputs.env}"
source "$OUTPUT_FILE"

echo "Checking $PUBLIC_URL/health"
for attempt in $(seq 1 30); do
  if curl -fsS "$PUBLIC_URL/health"; then
    echo
    echo "Deployment is healthy: $PUBLIC_URL"
    exit 0
  fi
  sleep 10
done

echo "Health check failed after waiting." >&2
exit 1
