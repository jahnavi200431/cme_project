#!/bin/bash
set -euo pipefail

# === CONFIG ===
PROJECT_ID="${PROJECT_ID:-my-project-app-477009}"
EMAIL="${EMAIL:-mallelajahnavi123@gmail.com}"
API_HOST="${API_HOST:-127.0.0.1}"          # LoadBalancer IP; passed as env
ENDPOINTS=("/products" "/products/1")      # Add more endpoints if needed
CHECK_PERIOD="5"                           # minutes
TIMEOUT="10"                               # seconds

# === 1. Set project ===
echo "Setting GCP project..."
gcloud config set project "$PROJECT_ID"

# === 2. Create Notification Channel ===
echo "Creating notification channel..."
CHANNEL_ID=$(gcloud alpha monitoring channels create \
  --type=email \
  --display-name="API Uptime Email Alerts" \
  --channel-labels=email_address="$EMAIL" \
  --format="value(name)")

echo "Notification Channel ID: $CHANNEL_ID"

# === 3. Create Uptime Checks and Alert Policies ===
for PATH in "${ENDPOINTS[@]}"; do
    # Replace / with - for valid resource names
    CHECK_NAME="gke-rest-api-${PATH//\//-}"
    echo "Creating uptime check for endpoint $PATH ..."

    # Create the uptime check
    UPTIME_CHECK_ID=$(gcloud monitoring uptime create "$CHECK_NAME" \
        --synthetic-target=http \
        --host="$API_HOST" \
        --path="$PATH" \
        --port=80 \
        --period="$CHECK_PERIOD" \
        --timeout="$TIMEOUT" \
        --format="value(name)")

    echo "Uptime Check created: $UPTIME_CHECK_ID"

    # Create alert policy JSON directly
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
        "trigger": { "count": 1 }
      }
    }
  ],
  "notificationChannels": ["$CHANNEL_ID"]
}
EOF

    echo "Creating alert policy for $PATH ..."
    gcloud alpha monitoring policies create --policy-from-file=policy.json
    echo "Alert policy created for $PATH."
done

echo "✅ All uptime checks and alerts created successfully!"
