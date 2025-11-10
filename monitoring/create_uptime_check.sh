#!/usr/bin/env bash
# Create/update synthetic uptime checks for multiple API endpoints using the Monitoring REST API.
# Uses gcloud to discover existing checks and to obtain an access token for the REST calls.
#
# Usage:
#   ./monitoring/create_synthetic_checks.sh \
#     --project=my-project-app-477009 \
#     --host=34.133.250.137 \
#     --paths="/products,/health,/metrics" \
#     --name-prefix=gke-rest-api \
#     --notification-channel="projects/my-project-app-477009/notificationChannels/12064618237516244045"
set -euo pipefail

PROJECT="my-project-app-477009"
HOST="34.133.250.137"
PATHS="/products"
NAME_PREFIX="gke-rest-api"
NOTIF_CHANNEL_ID="projects/my-project-app-477009/notificationChannels/12064618237516244045"

usage() {
  cat <<EOF
Usage: $0 --host=HOST [--project=PROJECT] [--paths=/p1,/p2] [--name-prefix=PREFIX] [--notification-channel=CHANNEL_ID]

Example:
  $0 --host=34.133.250.137 --paths="/products,/health" --notification-channel="projects/.../notificationChannels/123"
EOF
}

# parse args (support --key=value and --key value)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project=*) PROJECT="${1#*=}"; shift;;
    --project) PROJECT="$2"; shift 2;;
    --host=*) HOST="${1#*=}"; shift;;
    --host) HOST="$2"; shift 2;;
    --paths=*) PATHS="${1#*=}"; shift;;
    --paths) PATHS="$2"; shift 2;;
    --name-prefix=*) NAME_PREFIX="${1#*=}"; shift;;
    --name-prefix) NAME_PREFIX="$2"; shift 2;;
    --notification-channel=*) NOTIF_CHANNEL_ID="${1#*=}"; shift;;
    --notification-channel) NOTIF_CHANNEL_ID="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

if [ -z "${HOST:-}" ]; then
  echo "ERROR: --host is required"
  usage
  exit 2
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "ERROR: gcloud not found in PATH"
  exit 2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl not found in PATH"
  exit 2
fi

echo "Project: $PROJECT"
echo "Host: $HOST"
echo "Paths: $PATHS"
echo "Display name prefix: $NAME_PREFIX"
if [ -n "${NOTIF_CHANNEL_ID:-}" ]; then
  echo "Notification channel: $NOTIF_CHANNEL_ID"
fi

# Ensure Monitoring API seems enabled (informational)
if ! gcloud services list --project="$PROJECT" --enabled --filter="name:monitoring.googleapis.com" --format="value(config.name)" >/dev/null 2>&1; then
  echo "Warning: Cloud Monitoring API may not be enabled in project $PROJECT. If creation fails run:"
  echo "  gcloud services enable monitoring.googleapis.com --project=$PROJECT"
fi

# helper to create an uptime check via REST API
create_uptime_check() {
  local display_name="$1"
  local path="$2"

  read -r -d '' PAYLOAD <<EOF || true
{
  "displayName": "${display_name}",
  "httpCheck": {
    "path": "${path}",
    "port": 80,
    "requestMethod": "GET",
    "contentMatchers": []
  },
  "timeout": "10s",
  "period": "300s",
  "monitoredResource": {
    "type": "uptime_url",
    "labels": {
      "host": "${HOST}",
      "project_id": "${PROJECT}"
    }
  }
}
EOF

  token=$(gcloud auth print-access-token)
  resp=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    "https://monitoring.googleapis.com/v3/projects/${PROJECT}/uptimeCheckConfigs" \
    -d "${PAYLOAD}")

  http_code=$(echo "$resp" | tail -n1)
  body=$(echo "$resp" | sed '$d')
  if [[ "$http_code" =~ ^2 ]]; then
    echo "Created uptime check '${display_name}':"
    echo "$body"
    return 0
  else
    echo "ERROR creating uptime check '${display_name}' (HTTP $http_code):"
    echo "$body"
    return 1
  fi
}

# helper to create an alerting policy for a host/path (best-effort)
create_alert_policy() {
  local display_name="$1"

  read -r -d '' POLICY <<EOF || true
{
  "displayName":"${display_name}-alert",
  "combiner":"OR",
  "conditions":[
    {
      "displayName":"${display_name} - check failed",
      "conditionThreshold":{
        "filter":"metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" resource.type=\"uptime_url\" resource.label.\"host\"=\"${HOST}\"",
        "comparison":"COMPARISON_LT",
        "thresholdValue":1,
        "duration":"00:05:00",
        "trigger":{"count":1}
      }
    }
  ],
  "notificationChannels":[
    "${NOTIF_CHANNEL_ID}"
  ],
  "enabled":true
}
EOF

  # Try to find existing policy with the same displayName
  EXISTING_POLICY=$(gcloud monitoring policies list --project="$PROJECT" --filter="displayName=${display_name}-alert" --format="value(name)" 2>/dev/null || true)
  if [ -n "$EXISTING_POLICY" ]; then
    echo "Alerting policy already exists: $EXISTING_POLICY (skipping create)"
    return 0
  fi

  token=$(gcloud auth print-access-token)
  resp=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    "https://monitoring.googleapis.com/v3/projects/${PROJECT}/alertPolicies" \
    -d "${POLICY}")

  http_code=$(echo "$resp" | tail -n1)
  body=$(echo "$resp" | sed '$d')
  if [[ "$http_code" =~ ^2 ]]; then
    echo "Created alerting policy for '${display_name}':"
    echo "$body"
    return 0
  else
    echo "WARNING: failed to create alerting policy for '${display_name}' (HTTP $http_code)"
    echo "$body"
    return 1
  fi
}

# split PATHS by comma and iterate
IFS=',' read -r -a p_arr <<< "$PATHS"
for raw in "${p_arr[@]}"; do
  # trim whitespace
  p="$(echo "$raw" | awk '{$1=$1};1')"
  [ -z "$p" ] && continue
  case "$p" in
    /*) ;; # ok
    *) p="/$p";;
  esac

  # safe display name (replace / with - and remove leading -)
  safe="$(echo "$p" | sed 's|/|-|g' | sed 's|^-||')"
  display_name="${NAME_PREFIX}-${safe}"

  echo "==> Processing ${p} -> displayName='${display_name}'"

  # check existing uptime checks using gcloud (list-configs supports this environment)
  EXISTING=$(gcloud monitoring uptime list-configs --project="$PROJECT" --filter="displayName=${display_name}" --format="value(name)" 2>/dev/null || true)
  if [ -n "$EXISTING" ]; then
    echo "Found existing uptime check: $EXISTING (skipping creation)"
    continue
  fi

  # create uptime check
  if create_uptime_check "${display_name}" "${p}"; then
    # create alert policy only if notification channel provided
    if [ -n "${NOTIF_CHANNEL_ID:-}" ]; then
      create_alert_policy "${display_name}" || echo "Alert creation failed or skipped"
    fi
  else
    echo "Failed to create uptime check for ${p}; continuing with next path"
  fi
done

echo "All done."
