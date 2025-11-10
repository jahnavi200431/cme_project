#!/bin/bash

# === CONFIG ===
PROJECT_ID="my-project-app-477009"
CHECK_ID="gke-rest-api-products-9EIPgCWoV6w"
EMAIL="mallelajahnavi123@gmail.com"

# Set project
echo "Setting project..."
gcloud config set project $PROJECT_ID

# Create Notification Channel
echo "Creating notification channel..."
CHANNEL_ID=$(gcloud alpha monitoring channels create \
  --type=email \
  --display-name="Uptime Email Alerts" \
  --channel-labels=email_address=$EMAIL \
  --format="value(name)")

echo "Notification Channel ID: $CHANNEL_ID"

# Write alert policy file
echo "Writing policy.json..."
cat > policy.json <<EOF
{
  "displayName": "Uptime Check Failure Alert",
  "enabled": true,
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "Uptime Check Failed",
      "conditionMatchedLog": {
        "filter": "severity=\\"ERROR\\""
      }
    }
  ],
  "notificationChannels": ["$CHANNEL_ID"]
}
EOF


echo "policy.json created."

# Create alert policy
echo "Creating alert policy..."
gcloud alpha monitoring policies create --policy-from-file=policy.json

echo "✅ Setup completed successfully."

