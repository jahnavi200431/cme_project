#!/bin/bash
set -euo pipefail

# === CONFIG ===
PROJECT_ID="my-project-app-477009"
EMAIL="mallelajahnavi123@gmail.com"

# Existing uptime checks and their corresponding endpoints
declare -A UPTIME_CHECKS=(
    ["/products"]="gke-rest-api-products-9EIPgCWoV6w"
    ["/products/1"]="gke-rest-api-products-1-XXXXXXX"  # Replace with actual check ID
)

# === 1. Set GCP project ===
echo "🔧 Setting GCP project..."
gcloud config set project "$PROJECT_ID"

# === 2. Create Notification Channel ===
echo "📩 Creating notification channel..."
CHANNEL_ID=$(gcloud alpha monitoring channels create \
    --type=email \
    --display-name="API Uptime Email Alerts" \
    --channel-labels=email_address="$EMAIL" \
    --format="value(name)" || true)  # ignore if already exists

echo "Notification Channel ID: $CHANNEL_ID"

# === 3. Create Alert Policies using existing uptime checks ===
for PATH in "${!UPTIME_CHECKS[@]}"; do
    UPTIME_CHECK_ID="${UPTIME_CHECKS[$PATH]}"
    # Replace / with - for policy-friendly name
    CHECK_NAME="alert-${PATH//\//-}"

    echo "⚡ Creating alert policy for $PATH using existing uptime check $UPTIME_CHECK_ID..."

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

    # Apply the alert policy
    gcloud alpha monitoring policies create --policy-from-file=policy.json || true

    echo "✅ Alert policy created for $PATH."
done

echo "🎉 All alert policies created successfully using existing uptime checks!"
