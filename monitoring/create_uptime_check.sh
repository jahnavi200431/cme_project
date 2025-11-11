#!/bin/bash

# === CONFIG ===
PROJECT_ID="my-project-app-477009"
UPTIME_CHECK_ID="gke-rest-api-products-9EIPgCWoV6w"
EMAIL="mallelajahnavi123@gmail.com"

# === Set Project ===
echo "Setting project..."
gcloud config set project $PROJECT_ID

# === 1. Create Notification Channel (if not already created) ===
echo "Creating notification channel..."
CHANNEL_ID=$(gcloud alpha monitoring channels create \
  --type=email \
  --display-name="Uptime Email Alerts" \
  --channel-labels=email_address=$EMAIL \
  --format="value(name)")

echo "Notification Channel ID: $CHANNEL_ID"

# === 2. Write Alert Policy JSON ===
echo "Writing policy.json..."
cat > policy.json <<EOF
{
  "displayName": "API Uptime Failure Alert",
  "enabled": true,
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "API endpoint down",
      "conditionThreshold": {
        "filter": "resource.type=\\"uptime_url\\" AND metric.type=\\"monitoring.googleapis.com/uptime_check/check_passed\\" AND metric.label.uptime_check_id=\\"$UPTIME_CHECK_ID\\"",
        "comparison": "COMPARISON_LT",
        "thresholdValue": 1,
        "duration": "60s",
        "trigger": { "count": 1 }
      }
    }
  ],
  "notificationChannels": ["$CHANNEL_ID"]
}
EOF

echo "policy.json created."

# === 3. Create Alert Policy ===
echo "Creating alert policy..."
gcloud alpha monitoring policies create --policy-from-file=policy.json

echo "✅ Alert Policy created successfully. You will receive email alerts only when the API fails."
