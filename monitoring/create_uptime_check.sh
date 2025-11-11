#!/usr/bin/env bash
set -euo pipefail

# Defaults (can be overridden via flags)
PROJECT_ID="my-project-app-477009"
EMAIL="mallelajahnavi123@gmail.com"
API_HOST="34.133.250.137"
ENDPOINTS=("/products" "/products/1")
CHECK_PERIOD="5"
TIMEOUT="10"
NAME_PREFIX="gke-rest-api"
NOTIFICATION_CHANNEL=""

usage() {
  cat <<EOF
Usage: $0 [--project PROJECT_ID] [--host HOST] [--paths "/a,/b"] [--name-prefix PREFIX] [--notification-channel CHANNEL_RESOURCE] [--period MINUTES] [--timeout SECONDS] [--email EMAIL]
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
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

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
  # sanitize path WITHOUT external tools (no tr)
  trimmed="${PATH#/}"             # remove leading slash
  sanitized="${trimmed//\//-}"    # replace slashes with hyphens
  if [[ -z "$sanitized" ]]; then
    sanitized="root"
  fi

  CHECK_NAME="${NAME_PREFIX}-${sanitized}"
  echo "Creating uptime check for endpoint '$PATH' (check name: $CHECK_NAME)..."

  UPTIME_CHECK_ID=$(gcloud monitoring uptime create "$CHECK_NAME" \
    --synthetic-target=http \
    --host="$API_HOST" \
    --path="$PATH" \
    --port=80 \
    --period="$CHECK_PERIOD" \
    --timeout="$TIMEOUT" \
    --format="value(name)")

  echo "Uptime Check created: $UPTIME_CHECK_ID"

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
        "filter": "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND resource.label.check_id=\"$UPTIME_CHECK_ID\"",
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

echo "✅ All uptime checks and alerts created successfully!"
