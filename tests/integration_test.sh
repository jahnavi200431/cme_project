#!/usr/bin/env bash
# Extended integration tests for gke-rest-api service.
# Expects LB environment variable set to the LoadBalancer IP (LB).
# Tests:
#  - GET /products
#  - POST /products (create)
#  - GET /products/{id}
#  - PUT /products/{id} (update)
#  - DELETE /products/{id}
#
# The script exits non-zero on failure and prints helpful diagnostics.

set -euo pipefail

LB="34.133.250.137"
if [ -z "$LB" ]; then
  echo "ERROR: LB environment variable not set. Provide the LoadBalancer IP via LB."
  exit 2
fi

BASE_URL="http://$LB:80"
echo "Integration tests target: $BASE_URL"
TMPDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

# Helper: send request and return body and http status
# Args: method path [data-json]
request() {
  local method="$1"; shift
  local path="$1"; shift
  local data="${1:-}"
  local resp
  if [ -n "$data" ]; then
    # capture body + status
    resp=$(curl -s -S -w "\n%{http_code}" -H "Content-Type: application/json" -X "$method" "$BASE_URL$path" -d "$data" || true)
  else
    resp=$(curl -s -S -w "\n%{http_code}" -X "$method" "$BASE_URL$path" || true)
  fi
  local status
  status=$(echo "$resp" | tail -n1)
  local body
  body=$(echo "$resp" | sed '$d')
  echo "$status" > "$TMPDIR/status"
  echo "$body" > "$TMPDIR/body"
  return 0
}

# Helper: extract status/body from TMPDIR
get_status() { cat "$TMPDIR/status"; }
get_body() { cat "$TMPDIR/body"; }

# Helper: extract id from JSON body (try jq, then regex)
extract_id() {
  local body
  body="$(get_body)"
  local id

  if command -v jq >/dev/null 2>&1; then
    id=$(echo "$body" | jq -r '.id // empty' 2>/dev/null || true)
  fi

  if [ -z "$id" ]; then
    # try numeric or string id extraction: "id": 123  or  "id":"123"
    id=$(echo "$body" | grep -oE '"id"[[:space:]]*:[[:space:]]*("[^"]+"|[0-9]+)' || true)
    if [ -n "$id" ]; then
      id=$(echo "$id" | sed -E 's/.*:[[:space:]]*"?([^"]+)"?/\1/')
    fi
  fi

  echo "$id"
}

# 1) GET /products
echo "1) GET /products -> expecting HTTP 200"
request GET /products
status=$(get_status)
if [ "$status" != "200" ]; then
  echo "FAIL: GET /products returned HTTP $status"
  echo "Body:"
  get_body || true
  exit 1
fi
echo "OK: GET /products returned 200"

# 2) POST /products (create)
echo "2) POST /products -> creating a test product"
UNIQUE="$(date +%s)-$RANDOM"
payload=$(cat <<EOF
{
  "name": "integration-test-product-$UNIQUE",
  "description": "Created by integration_test.sh",
  "price": 9.99
}
EOF
)
request POST /products "$payload"
post_status=$(get_status)
post_body=$(get_body)
echo "POST response status: $post_status"
echo "POST response body: $post_body"

if [ "$post_status" != "201" ] && [ "$post_status" != "200" ]; then
  echo "FAIL: POST /products returned HTTP $post_status (expected 201 or 200)"
  exit 1
fi

product_id=$(extract_id)
if [ -z "$product_id" ]; then
  # try Location header (if server returned it)
  headers=$(curl -s -i -H "Content-Type: application/json" -X POST "$BASE_URL/products" -d "$payload" || true)
  # look for Location: .../products/{id}
  product_id=$(echo "$headers" | grep -i -oE 'Location: .*' | sed -E 's|.*/products/([^/[:space:]]+).*|\1|' | tr -d '\r' || true)
fi

if [ -z "$product_id" ]; then
  echo "FAIL: Could not extract created product id from response. Body:"
  echo "$post_body"
  exit 1
fi

echo "OK: Created product id = $product_id"

# 3) GET /products/{id}
echo "3) GET /products/$product_id -> expecting HTTP 200 and matching name"
request GET "/products/$product_id"
get_id_status=$(get_status)
get_id_body=$(get_body)
if [ "$get_id_status" != "200" ]; then
  echo "FAIL: GET /products/$product_id returned HTTP $get_id_status"
  echo "Body: $get_id_body"
  exit 1
fi

# quick sanity: ensure name string present
if ! echo "$get_id_body" | grep -q "integration-test-product"; then
  echo "WARN: GET /products/$product_id body does not contain expected name. Body:"
  echo "$get_id_body"
fi
echo "OK: GET /products/$product_id returned 200"

# 4) PUT /products/{id} (update)
echo "4) PUT /products/$product_id -> updating product name"
updated_payload=$(cat <<EOF
{
  "name": "integration-test-product-$UNIQUE-updated",
  "description": "Updated by integration_test.sh",
  "price": 19.99
}
EOF
)
request PUT "/products/$product_id" "$updated_payload"
put_status=$(get_status)
put_body=$(get_body)
echo "PUT response status: $put_status"
if [ "$put_status" != "200" ] && [ "$put_status" != "204" ]; then
  echo "FAIL: PUT /products/$product_id returned HTTP $put_status (expected 200 or 204)"
  echo "Body: $put_body"
  exit 1
fi

# If PUT returned 204 (no body), perform a GET to verify update
request GET "/products/$product_id"
verify_status=$(get_status)
verify_body=$(get_body)
if [ "$verify_status" != "200" ]; then
  echo "FAIL: After PUT, GET /products/$product_id returned HTTP $verify_status"
  echo "Body: $verify_body"
  exit 1
fi

if ! echo "$verify_body" | grep -q "updated"; then
  echo "FAIL: Updated product response does not show updated fields. Body:"
  echo "$verify_body"
  exit 1
fi
echo "OK: Product updated and verified"

# 5) DELETE /products/{id}
echo "5) DELETE /products/$product_id -> deleting product"
request DELETE "/products/$product_id"
del_status=$(get_status)
del_body=$(get_body)
echo "DELETE returned status: $del_status"
if [ "$del_status" != "200" ] && [ "$del_status" != "204" ] && [ "$del_status" != "202" ]; then
  echo "FAIL: DELETE /products/$product_id returned HTTP $del_status (expected 200/202/204)"
  echo "Body: $del_body"
  exit 1
fi

# Verify deletion: GET should return 404 (or 410) or not found
request GET "/products/$product_id"
post_del_status=$(get_status)
post_del_body=$(get_body)
if [ "$post_del_status" = "200" ]; then
  echo "FAIL: After DELETE, GET /products/$product_id returned 200 (expected 404/410/not found). Body:"
  echo "$post_del_body"
  exit 1
fi
echo "OK: DELETE verified (GET returned HTTP $post_del_status)"

echo "All integration tests passed."
