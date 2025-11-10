#!/usr/bin/env bash
# Simple integration test script for the gke-rest-api service.
# Expects LB IP in environment variable LB (set by cloudbuild step).
# Exits non-zero on failure.

set -euo pipefail

LB="${LB:-}"
if [ -z "$LB" ]; then
  echo "ERROR: LB environment variable not set. Provide the LoadBalancer IP via LB."
  exit 2
fi

BASE_URL="http://$LB:80"
echo "Integration tests target: $BASE_URL"

# Helper: check endpoint returns expected HTTP status
check_status() {
  local path="$1"
  local expected="$2"
  echo "Checking $path -> expecting HTTP $expected"
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$BASE_URL$path" || echo "000")
  if [ "$code" != "$expected" ]; then
    echo "FAIL: $path returned HTTP $code (expected $expected)"
    return 1
  fi
  echo "OK: $path returned $code"
  return 0
}

# 1) /products should return 200
check_status "/products" "200"

# 2) Optionally test that list is JSON (try to parse using jq if available)
body=$(curl -s --max-time 10 "$BASE_URL/products" || true)
if [ -n "$body" ]; then
  # quick sanity: body should contain '[' or '{' for JSON
  if ! echo "$body" | grep -Eq '^\s*[\[\{]'; then
    echo "WARN: /products response does not look like JSON"
  fi
else
  echo "Warning: /products returned empty body"
fi

# Add more endpoint checks here (POST/PUT/DELETE) as needed and authentication tests.

echo "All integration checks passed."