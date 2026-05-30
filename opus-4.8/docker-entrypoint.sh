#!/bin/sh
set -e

echo "[entrypoint] running database migrations..."
node scripts/migrate.mjs

echo "[entrypoint] starting Next.js server on port ${PORT:-3000}..."
exec node server.js
