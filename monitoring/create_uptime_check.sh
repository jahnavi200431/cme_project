#!/usr/bin/env bash
# Create or update a Cloud Monitoring uptime check for the /products endpoint,
# and optionally create an alerting policy that notifies a provided notification channel.
#
# Usage:
#   ./monitoring/create_uptime_check.sh --project=my-project-app-477009 --lb-ip=34.133.250.137 [--name=gke-rest-api-products] [--notification-channel=CHANNEL_ID]
#
# Requirements:
# - gcloud installed and authenticated
# - Monitoring API enabled (and alpha for uptime-checks if using alpha)
# - Caller must have monitoring.uptimeCheckConfigs.create / update permissions
#
set -euo pipefail

PROJECT="my-project-app-477009"
LB_IP=""
CHECK_NAME="gke-rest-api-products"
NOTIF_CHANNEL_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2;;
    --lb-ip) LB_IP="$2"; shift 2;;
    --name) CHECK_NAME="$2"; shift 2;;
    --notification-channel) NOTIF_CHANNEL_ID="$2"; shift 2;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

if [ -z "$LB_IP" ]; then
  echo "ERROR: --lb-ip is required"
  exit 2
fi

echo "Project: $PROJECT"
echo "LB IP: $LB_IP"
echo "Check name: $CHECK_NAME"
if [ -n "$NOTIF_CHANNEL_ID" ]; then
  echo "Notification channel: $NOTIF_CHANNEL_ID"
fi

# Look for an existing uptime check with this display name
EXISTING_CHECK=$(gcloud alpha monitoring uptime-checks list \
  --project="$PROJECT" \
  --filter="displayName = \"${CHECK_NAME}\"" \
  --format="value(name)" 2>/dev/null || true)

if [ -n "$EXISTING_CHECK" ]; then
  echo "Found existing uptime check: $EXISTING_CHECK"
  CHECK_ID="$EXISTING_CHECK"
else
  echo "Creating uptime check ${CHECK_NAME} -> http://${LB_IP}/products"
  CHECK_ID=$(gcloud alpha monitoring uptime-checks create http \
    --project="$PROJECT" \
    --display-name="$CHECK_NAME" \
    --host="$LB_IP" \
    --path="/products" \
    --port=80 \
    --http-check-response-code=200 \
    --timeout=10s \
    --period=300s \
    --content-matchers='[]' \
    --format="value(name)")
  echo "Created uptime check: $CHECK_ID"
fi

# If a notification channel ID is provided, create a simple alerting policy
if [ -n "$NOTIF_CHANNEL_ID" ]; then
  echo "Attempting to create/update an alerting policy for the uptime check..."

  # Build a minimal policy JSON referencing the uptime-check metric filter.
  # Note: We're using the uptime_check metric "monitoring.googleapis.com/uptime_check/check_passed"
  # where a value of 0 indicates failure. This policy triggers when the check fails.
  POLICY_JSON=$(mktemp)
  cat > "$POLICY_JSON" <<EOF
{
  "displayName": "${CHECK_NAME}-alert",
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "${CHECK_NAME} - check failed",
      "conditionThreshold": {
        "filter": "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" resource.type=\"uptime_url\" resource.label.\"host\"=\"${LB_IP}\"",
        "comparison": "COMPARISON_LT",
        "thresholdValue": 1,
        "duration": "00:05:00",
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "notificationChannels": [
    "${NOTIF_CHANNEL_ID}"
  ],
  "enabled": true
}
EOF

  # Try to create the policy. If a policy with this displayName exists, attempt to update it.
  EXISTING_POLICY=$(gcloud alpha monitoring policies list --project="$PROJECT" --filter="displayName=${CHECK_NAME}-alert" --format="value(name)" 2>/dev/null || true)
  if [ -n "$EXISTING_POLICY" ]; then
    echo "Found existing alerting policy: $EXISTING_POLICY -> updating"
    gcloud alpha monitoring policies update "$EXISTING_POLICY" --project="$PROJECT" --policy-from-file="$POLICY_JSON" || echo "Failed to update alerting policy"
  else
    echo "Creating new alerting policy: ${CHECK_NAME}-alert"
    gcloud alpha monitoring policies create --project="$PROJECT" --policy-from-file="$POLICY_JSON" || echo "Failed to create alerting policy"
  fi

  rm -f "$POLICY_JSON"
  echo "Alerting policy created/updated (if permissions allowed)."
else
  echo "No notification channel id provided; skipping alerting policy creation."
fi

echo "Done."