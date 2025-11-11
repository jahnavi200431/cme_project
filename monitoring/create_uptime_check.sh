#!/usr/bin/env bash
set -euo pipefail

# This script will NOT create uptime checks. It only uses existing uptime check IDs
# to create alert policies. You must provide --existing-check-id (applies to all paths)
# or --existing-checks "/path=CHECK_ID,/p2=ID2" to map paths to check IDs.

PROJECT_ID="my-project-app-477009"
EMAIL="mallelajahnavi123@gmail.com"
API_HOST="34.133.250.137"
ENDPOINTS=("/products" "/products/1")
CHECK_PERIOD="5"
TIMEOUT="10"
NAME_PREFIX="gke-rest-api"
NOTIFICATION_CHANNEL=""
EXISTING_CHECK_ID="gke-rest-api-products-9EIPgCWoV6w"
EXISTING_CHECKS=""

usage() {
  cat <<EOF
Usage: $0 --existing-checks "/path=CHECK_ID,..." | --existing-check-id ID [options]
Options:
  --project PROJECT_ID
  --host HOST
  --paths "/a,/b"
  --name-prefix PREFIX
  --notification-channel CHANNEL_RESOURCE
  --period MINUTES
  --timeout SECONDS
  --email EMAIL
  --existing-check-id ID
  --existing-checks "/path=ID,/other=ID2"
Note: The script will NOT create uptime checks. Provide existing check IDs to use.
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT_ID="$2"; shift 2;;
    --host) API_HOST="$2"; shift 2;;
    --paths) IFS=',' read -r -a ENDPOINTS <<< "$2"; shift 2;;
    --name-prefix) NAME_PREFIX="$2"; shift 2;;
    --notification-channel) NOTIFICATION_CHANNEL="$2"; shift 2;;
    --period) CHECK_PERIOD="$2"; shift 2;;
    --timeout) TIMEOUT="$2"; shift 2;;
    --email) EMAIL="$2"; shift 2;;
    --existing-check-id) EXISTING_CHECK_ID="$2"; shift 2;;
    --existing-checks) EXISTING_CHECKS="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

# build a map of provided existing checks
declare -A EXISTING_MAP
if [[ -n "$EXISTING_CHECKS" ]]; then
  OLDIFS="$IFS"
  IFS=',' read -ra pairs <<< "$EXISTING_CHECKS"
  for p in "${pairs[@]}"; do
    p="${p#"${p%%[![:space:]]*}"}"
    p="${p%"${p##*[![:space:]]}"}"
    if [[ "$p" == *"="* ]]; then
      key="${p%%=*}"
      val="${p#*=}"
      EXISTING_MAP["$key"]="$val"
    fi
  done
  IFS="$OLDIFS"
fi

if [[ -z "$EXISTING_CHECK_ID" && ${#EXISTING_MAP[@]} -eq 0 ]]; then
  echo "ERROR: No existing uptime check IDs provided. This script will not create uptime checks."
  echo "Provide --existing-check-id or --existing-checks \"/path=CHECK_ID,...\""
  exit 1
fi

echo "Setting GCP project..."
gcloud config set project "$PROJECT_ID"

if [[ -n "$NOTIFICATION_CHANNEL" ]]; then
  CHANNEL_ID="$NOTIFICATION_CHANNEL"
  echo "Using provided notification channel: $CHANNEL_ID"
else
  echo "Creating notification channel for $EMAIL..."
  CHANNEL_ID=$(gcloud alpha monitoring channels create \
    --type=email \
    --display-name="${NAME_PREFIX} Email Alerts" \
    --channel-labels=email_address="$EMAIL" \
    --format="value(name)")
  echo "Notification Channel ID: $CHANNEL_ID"
fi

for PATH in "${ENDPOINTS[@]}"; do
  # sanitize path for filenames without external tools
  trimmed="${PATH#/}"
  sanitized="${trimmed//\//-}"
  if [[ -z "$sanitized" ]]; then
    sanitized="root"
  fi
  CHECK_NAME="${NAME_PREFIX}-${sanitized}"
  echo "Preparing alert policy for endpoint '$PATH' (policy file will be policy-${CHECK_NAME}.json)..."

  # determine which existing check ID to use for this path
  UPTIME_CHECK_ID=""
  if [[ -n "${EXISTING_MAP[$PATH]:-}" ]]; then
    UPTIME_CHECK_ID="${EXISTING_MAP[$PATH]}"
    echo "Using mapping for $PATH -> $UPTIME_CHECK_ID"
  elif [[ -n "$EXISTING_CHECK_ID" ]]; then
    UPTIME_CHECK_ID="$EXISTING_CHECK_ID"
    echo "Using provided existing-check-id for $PATH -> $UPTIME_CHECK_ID"
  else
    echo "ERROR: No check ID for path $PATH. Provide mapping for this path or a global --existing-check-id."
    exit 1
  fi

  POLICY_FILE="policy-${CHECK_NAME}.json"
  cat > "$POLICY_FILE" <<EOF
{
  "displayName": "API Failure Alert - $PATH",
  "enabled": true,
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "API Endpoint $PATH Failed",
      "conditionThreshold": {
        "filter": "metric.type=\\"monitoring.googleapis.com/uptime_check/check_passed\\" AND resource.type=\\"uptime_url\\" AND resource.label.check_id=\\"$UPTIME_CHECK_ID\\"",
        "comparison": "COMPARISON_LT",
        "thresholdValue": 1,
        "duration": "0s",
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "notificationChannels": ["$CHANNEL_ID"]
}
EOF

  echo "Creating alert policy for $PATH from $POLICY_FILE..."
  gcloud alpha monitoring policies create --policy-from-file="$POLICY_FILE"
  echo "Alert policy created for $PATH."
done

echo "✅ All alert policies created/updated using existing uptime checks."
