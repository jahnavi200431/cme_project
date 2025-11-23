#!/bin/bash
set -euo pipefail

# ---------------------------
# Validate required env var
# ---------------------------
: "${LB:?ERROR: LB environment variable not set}"
: "${API_KEY:?ERROR: API_KEY environment variable not set}"

BASE_URL="http://$LB:80"
echo "Integration tests target: $BASE_URL"

TMPDIR="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

# ---------------------------
# Helper functions
# ---------------------------
request() {
  local method="$1"
  local path="$2"
  local data="${3:-}"

  local resp
  if [ -n "$data" ]; then
    resp=$(curl -s -S -w "\n%{http_code}" \
      -H "Content-Type: application/json" \
      -H "X-API-KEY: $API_KEY" \
      -X "$method" "$BASE_URL$path" -d "$data" 2>/dev/null || true)
  else
    resp=$(curl -s -S -w "\n%{http_code}" \
      -H "X-API-KEY: $API_KEY" \
      -X "$method" "$BASE_URL$path" 2>/dev/null || true)
  fi

  echo "$resp" | tail -n1 > "$TMPDIR/status"
  echo "$resp" | sed '$d' > "$TMPDIR/body"
}

get_status() { cat "$TMPDIR/status"; }
get_body() { cat "$TMPDIR/body"; }

extract_id() {
  local body
  body="$(get_body)"

  if command -v jq >/dev/null 2>&1; then
    jq -r '.id // empty' <<<"$body" 2>/dev/null || true
    return
  fi

  echo "$body" | grep -oE '"id"\s*:\s*("[^"]+"|[0-9]+)' |
    sed -E 's/.*:\s*"?([^"]+)"?/\1/' || true
}

# ---------------------------
# Test steps
# ---------------------------

echo "1) GET /products (expecting 200)"
request GET /products
if [ "$(get_status)" != "200" ]; then
  echo "FAIL: GET /products -> $(get_status)"
  get_body
  exit 1
fi
echo "OK"

echo "2) POST /products (creating item)"
UNIQUE="$(date +%s)-$RANDOM"
payload=$(cat <<EOF
{
  "name": "integration-test-product-$UNIQUE",
  "description": "Created by integration tests",
  "price": 9.99
}
EOF
)

request POST /products "$payload"
status="$(get_status)"

if [[ "$status" != "200" && "$status" != "201" ]]; then
  echo "FAIL: POST returned $status"
  get_body
  exit 1
fi

product_id=$(extract_id)
if [ -z "$product_id" ]; then
  echo "FAIL: Could not extract product id"
  exit 1
fi
echo "Created product id: $product_id"

echo "3) GET /products/$product_id"
request GET "/products/$product_id"
if [ "$(get_status)" != "200" ]; then
  echo "FAIL: GET returned $(get_status)"
  get_body
  exit 1
fi
echo "OK"

echo "4) PUT /products/$product_id (update)"
updated_payload=$(cat <<EOF
{
  "name": "integration-test-product-$UNIQUE-updated",
  "description": "Updated by integration tests",
  "price": 19.99
}
EOF
)

request PUT "/products/$product_id" "$updated_payload"
if [[ "$(get_status)" != "200" && "$(get_status)" != "204" ]]; then
  echo "FAIL: PUT returned $(get_status)"
  get_body
  exit 1
fi

request GET "/products/$product_id"
if [ "$(get_status)" != "200" ]; then
  echo "FAIL: Follow-up GET failed"
  exit 1
fi
echo "OK"

echo "5) DELETE /products/$product_id"
request DELETE "/products/$product_id"
if [[ "$(get_status)" != "200" && "$(get_status)" != "204" && "$(get_status)" != "202" ]]; then
  echo "FAIL: DELETE returned $(get_status)"
  exit 1
fi

request GET "/products/$product_id"
if [ "$(get_status)" = "200" ]; then
  echo "FAIL: resource still exists after DELETE"
  exit 1
fi
echo "Deletion verified"

echo "✅ All integration tests PASSED"
exit 0
