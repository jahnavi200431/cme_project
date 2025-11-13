#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------------------------
# This script does NOT create new uptime checks — it only uses existing uptime check IDs
# to create alert policies in Google Cloud Monitoring.
# -------------------------------------------------------------------------------------

# Default values
PROJECT_ID="my-project-app-477009"
EMAIL="mallelajahnavi123@gmail.com"
API_HOST="34.133.250.137"
ENDPOINTS=("/products")
CHECK_PERIOD="5"
TIMEOUT="10"
NAME_PREFIX="gke-rest-api"
NOTIFICATION_CHANNEL="projects/my-project-app-477009/notificationChannels/1434793113408835929"
EXISTING_CHECK_ID="gke-rest-api-products-9EIPgCWoV6w"
EXISTING_CHECKS="gke-rest-api-products-9EIPgCWoV6w"

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

# --- Argument Parser (supports --flag=value or --flag value) ---
while [[ $# -gt 0 ]]; do
  arg="$1"
  case "$arg" in
    --project=*) PROJECT_ID="${arg#*=}"; shift;;
    --project) PROJECT_ID="$2"; shift 2;;

    --host=*) API_HOST="${arg#*=}"; shift;;
    --host) API_HOST="$2"; shift 2;;

    --paths=*) IFS=',' read -r -a ENDPOINTS <<< "${arg#*=}"; shift;;
    --paths) IFS=',' read -r -a ENDPOINTS <<< "$2"; shift 2;;

    --name-prefix=*) NAME_PREFIX="${arg#*=}"; shift;;
    --name-prefix) NAME_PREFIX="$2"; shift 2;;

    --notification-channel=*) NOTIFICATION_CHANNEL="${arg#*=}"; shift;;
    --notification-channel) NOTIFICATION_CHANNEL="$2"; shift 2;;

    --period=*) CHECK_PERIOD="${arg#*=}"; shift;;
    --period) CHECK_PERIOD="$2"; shift 2;;

    --timeout=*) TIMEOUT="${arg#*=}"; shift;;
    --timeout) TIMEOUT="$2"; shift 2;;

    --email=*) EMAIL="${arg#*=}"; shift;;
    --email) EMAIL="$2"; shift 2;;

    --existing-check-id=*) EXISTING_CHECK_ID="${arg#*=}"; shift;;
    --existing-check-id) EXISTING_CHECK_ID="$2"; shift 2;;

    --existing-checks=*) EXISTING_CHECKS="${arg#*=}"; shift;;
    --existing-checks) EXISTING_CHECKS="$2"; shift 2;;

    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

# --- Validate Inputs ---
if [[ -z "$PROJECT_ID" ]]; then
  echo "ERROR: Missing --project argument."
  usage
fi

if [[ -z "$EMAIL" ]]; then
  echo "ERROR: Missing --email argument."
  usage
fi

if [[ -z "$API_HOST" ]]; then
  echo "ERROR: Missing --host argument."
  usage
fi

if [[ -z "$EXISTING_CHECK_ID" && -z "$EXISTING_CHECKS" ]]; then
  echo "ERROR: No existing uptime check IDs provided."
  echo "Provide --existing-check-id or --existing-checks \"/path=CHECK_ID,...\""
  exit 1
fi

# --- Parse existing checks mapping ---
declare -A EXISTING_MAP
if [[ -n "$EXISTING_CHECKS" ]]; then
  OLDIFS="$IFS"
  IFS=',' read -ra pairs <<< "$EXISTING_CHECKS"
  for p in "${pairs[@]}"; do
    p="${p#"${p%%[![:space:]]*}"}"  # trim leading space
    p="${p%"${p##*[![:space:]]}"}"  # trim trailing space
    if [[ "$p" == *"="* ]]; then
      key="${p%%=*}"
      val="${p#*=}"
      EXISTING_MAP["$key"]="$val"
    fi
  done
  IFS="$OLDIFS"
fi

# --- Set GCP Project ---
echo "Setting GCP project to: $PROJECT_ID ..."
gcloud config set project "$PROJECT_ID"

# --- Create or use existing notification channel ---
if [[ -n "$NOTIFICATION_CHANNEL" ]]; then
  CHANNEL_ID="$NOTIFICATION_CHANNEL"
  echo "Using provided notification channel: $CHANNEL_ID"
else
  echo "Creating email notification channel for $EMAIL..."
  CHANNEL_ID=$(gcloud alpha monitoring channels create \
    --type=email \
    --display-name="${NAME_PREFIX} Email Alerts" \
    --channel-labels=email_address="$EMAIL" \
    --format="value(name)")
  echo "Notification Channel ID: $CHANNEL_ID"
fi

# --- Create alert policies for each path ---
for PATH in "${ENDPOINTS[@]}"; do
  trimmed="${PATH#/}"
  sanitized="${trimmed//\//-}"
  [[ -z "$sanitized" ]] && sanitized="root"
  CHECK_NAME="${NAME_PREFIX}-${sanitized}"

  echo "Preparing alert policy for endpoint '$PATH'..."

  # Determine which uptime check ID to use
  if [[ -n "${EXISTING_MAP[$PATH]:-}" ]]; then
    UPTIME_CHECK_ID="${EXISTING_MAP[$PATH]}"
    echo "Using mapped check ID for $PATH -> $UPTIME_CHECK_ID"
  elif [[ -n "$EXISTING_CHECK_ID" ]]; then
    UPTIME_CHECK_ID="$EXISTING_CHECK_ID"
    echo "Using global existing-check-id for $PATH -> $UPTIME_CHECK_ID"
  else
    echo "ERROR: No check ID found for $PATH"
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
        "trigger": { "count": 1 }
      }
    }
  ],
  "notificationChannels": ["$CHANNEL_ID"]
}
EOF

  echo "Creating alert policy for $PATH..."
  gcloud alpha monitoring policies create --policy-from-file="$POLICY_FILE"
  echo "✅ Alert policy created for $PATH"
done

echo "🎉 All alert policies created successfully using existing uptime checks."
