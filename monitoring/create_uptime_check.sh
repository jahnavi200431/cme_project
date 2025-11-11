#!/bin/bash

PROJECT_ID="my-project-app-477009"
EMAIL="mallelajahnavi123@gmail.com"

# Set project
gcloud config set project $PROJECT_ID

# Create Notification Channel
CHANNEL_ID=$(gcloud alpha monitoring channels create \
  --type=email \
  --display-name="Uptime Email Alerts" \
  --channel-labels=email_address=$EMAIL \
  --format="value(name)")

echo "Notification Channel ID: $CHANNEL_ID"

# Create Alert Policy for uptime check
cat > policy.json <<EOF
{
  "displayName": "API Uptime Failure Alert",
  "enabled": true,
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "API endpoint failed",
      "conditionMonitoringQueryLanguage": {
        "query": "fetch gce_instance::compute.googleapis.com/instance/disk/write_bytes | condition >= 0" 
      }
    }
  ],
  "notificationChannels": ["$CHANNEL_ID"],
  "alertStrategy": {
    "notificationRateLimit": {
      "period": "300s"
    }
  }
}
EOF

gcloud alpha monitoring policies create --policy-from-file=policy.json

echo "✅ Synthetic monitoring alert created!"
