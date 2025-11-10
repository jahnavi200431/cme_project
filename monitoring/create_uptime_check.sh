#!/bin/bash

# === CONFIG ===
PROJECT_ID="my-project-app-477009"
CHECK_NAME="gke-rest-api-uptime"
URL="http://34.133.250.137"
EMAIL="mallelajahnavi123@gmail.com"
REGION="us-central1"

# === AUTH ===
echo "Setting project..."
gcloud config set project $PROJECT_ID

# === 1. Create Notification Channel ===
echo "Creating notification channel..."
CHANNEL_ID=$(gcloud alpha monitoring channels create \
  --type=email \
  --display-name="Uptime Email Alerts" \
  --channel-labels=email_address=$EMAIL \
  --format="value(name)")

echo "Notification Channel ID: $CHANNEL_ID"

# === 2. Create Uptime Check ===
echo "Creating uptime check..."
UPTIME_CHECK_ID=$(gcloud monitoring uptime-checks create http \
  $CHECK_NAME \
  --path="/" \
  --host=$URL \
  --port=80 \
  --period=300s \
  --timeout=10s \
  --format="value(name)")

echo "Uptime Check created with ID: $UPTIME_CHECK_ID"

# === 3. Create Alert Policy JSON ===
echo "Writing alert policy json..."

cat > policy.json <<EOF
{
  "displayName": "Uptime Failure Alert",
  "enabled": true,
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "Uptime Check Failed",
      "conditionThreshold": {
        "filter": "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.check_id=\"$CHECK_NAME\"",
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

echo "policy.json generated."

# === 4. Create Alert Policy ===
echo "Creating alert policy..."
gcloud alpha monitoring policies create --policy-from-file=policy.json

echo "✅ Monitoring setup completed successfully!"
echo "✅ Uptime Check: $UPTIME_CHECK_ID"
echo "✅ Alert Policy Created"
echo "✅ Email Alerts will be sent to $EMAIL"

