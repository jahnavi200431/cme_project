#!/bin/bash

PROJECT_ID="my-project-app-477009"
EMAIL="mallelajahnavi123@gmail.com"
CHECK_NAME="gke-rest-api-products"

# Set project
echo "Setting project..."
gcloud config set project $PROJECT_ID

# Create notification channel
echo "Creating notification channel..."
CHANNEL_ID=$(gcloud alpha monitoring channels create \
  --type=email \
  --display-name="Uptime Email Alerts" \
  --channel-labels=email_address=$EMAIL \
  --format="value(name)")

echo "Notification Channel ID: $CHANNEL_ID"

# Create alert policy JSON for uptime check
cat > policy.json <<EOF
{
  "displayName": "API Uptime Failure Alert",
  "enabled": true,
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "API endpoint is down",
      "conditionThreshold": {
        "filter": "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.label.\"check_id\"=\"$CHECK_NAME\"",
        "comparison": "COMPARISON_LT",
        "thresholdValue": 1,
        "duration": "60s",
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "notificationChannels": ["$CHANNEL_ID"]
}
EOF

# Create alert policy
echo "Creating alert policy..."
gcloud alpha monitoring policies create --policy-from-file=policy.json

echo "✅ Synthetic monitoring alert created!"
