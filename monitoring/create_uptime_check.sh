#!/usr/bin/env bash
# Create or update a Cloud Monitoring uptime check for the /products endpoint.
# Usage:
#   ./monitoring/create_uptime_check.sh --project=my-project-app-477009 --lb-ip=34.133.250.137 [--name=name] [--notification-channel=CHANNEL_ID]
set -euo pipefail

# Defaults
PROJECT="my-project-app-477009"
LB_IP="34.133.250.137"
CHECK_NAME="gke-rest-api-products"
NOTIF_CHANNEL_ID="projects/my-project-app-477009/notificationChannels/12064618237516244045"

usage() {
  cat <<EOF
Usage: $0 --lb-ip=<ip> [--project=<project>] [--name=<check-name>] [--notification-channel=<channel-id>]

Options:
  --project                 GCP project id (default: ${PROJECT})
  --lb-ip                   LoadBalancer IP (required unless LB env set)
  --name                    Uptime check display name (default: ${CHECK_NAME})
  --notification-channel    Optional notification channel name/id to attach to an alerting policy
  --help                    Show this help and exit
EOF
}

# If GNU getopt is available, prefer it (supports --key=value)
if getopt --test >/dev/null 2>&1; then
  PARSED=$(getopt -o h --long help,project:,lb-ip:,name:,notification-channel: -- "$@") || { usage; exit 2; }
  eval set -- "$PARSED"
  while true; do
    case "$1" in
      --project) PROJECT="$2"; shift 2;;
      --lb-ip) LB_IP="$2"; shift 2;;
      --name) CHECK_NAME="$2"; shift 2;;
      --notification-channel) NOTIF_CHANNEL_ID="$2"; shift 2;;
      -h|--help) usage; exit 0;;
      --) shift; break;;
      *) echo "Unknown option: $1"; usage; exit 2;;
    esac
  done
else
  # Fallback parser: accepts both --key=value and --key value
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project=*) PROJECT="${1#*=}"; shift;;
      --project) PROJECT="$2"; shift 2;;
      --lb-ip=*) LB_IP="${1#*=}"; shift;;
      --lb-ip) LB_IP="$2"; shift 2;;
      --name=*) CHECK_NAME="${1#*=}"; shift;;
      --name) CHECK_NAME="$2"; shift 2;;
      --notification-channel=*) NOTIF_CHANNEL_ID="${1#*=}"; shift;;
      --notification-channel) NOTIF_CHANNEL_ID="$2"; shift 2;;
      -h|--help) usage; exit 0;;
      *) echo "Unknown arg: $1"; usage; exit 2;;
    esac
  done
fi

# Allow LB_IP from environment if not provided as flag
if [ -z "${LB_IP:-}" ] && [ -n "${LB:-}" ]; then
  LB_IP="$LB"
fi

if [ -z "${LB_IP:-}" ]; then
  echo "ERROR: --lb-ip is required (or set LB environment variable)."
  usage
  exit 2
fi

echo "Project: $PROJECT"
echo "LB IP: $LB_IP"
echo "Check name: $CHECK_NAME"
if [ -n "$NOTIF_CHANNEL_ID" ]; then
  echo "Notification channel: $NOTIF_CHANNEL_ID"
fi

# Ensure gcloud available
if ! command -v gcloud >/dev/null 2>&1; then
  echo "ERROR: gcloud not found in PATH"
  exit 2
fi

# Idempotent uptime check creation
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
    --format="value(name)" 2>/dev/null) || { echo "Failed to create uptime check"; exit 1; }
  echo "Created uptime check: $CHECK_ID"
fi

# Create/update alerting policy if channel provided
if [ -n "$NOTIF_CHANNEL_ID" ]; then
  echo "Creating/updating alerting policy for uptime check..."
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

  EXISTING_POLICY=$(gcloud alpha monitoring policies list --project="$PROJECT" --filter="displayName=${CHECK_NAME}-alert" --format="value(name)" 2>/dev/null || true)
  if [ -n "$EXISTING_POLICY" ]; then
    echo "Updating existing alerting policy: $EXISTING_POLICY"
    gcloud alpha monitoring policies update "$EXISTING_POLICY" --project="$PROJECT" --policy-from-file="$POLICY_JSON" || echo "Warning: failed to update alerting policy"
  else
    echo "Creating new alerting policy: ${CHECK_NAME}-alert"
    gcloud alpha monitoring policies create --project="$PROJECT" --policy-from-file="$POLICY_JSON" || echo "Warning: failed to create alerting policy"
  fi
  rm -f "$POLICY_JSON"
  echo "Alerting policy created/updated (if permissions allowed)."
else
  echo "No notification channel id provided; skipping alerting policy creation."
fi

echo "Done."
