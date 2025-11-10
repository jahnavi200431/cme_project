#!/bin/bash

# === CONFIG ===
PROJECT_ID="my-project-app-477009"
CHECK_NAME="gke-rest-api-uptime"
URL="34.133.250.137"
EMAIL="mallelajahnavi123@gmail.com"

# === Colors ===
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="\e[0m"

echo -e "${YELLOW}🔧 Setting up GCP Uptime + Alerts...${RESET}"

# === Set Project ===
echo -e "${YELLOW}📌 Setting project to $PROJECT_ID...${RESET}"
gcloud config set project $PROJECT_ID || { echo -e "${RED}Failed: Cannot set GCP project.${RESET}"; exit 1; }

# === 1. Create Notification Channel ===
echo -e "${YELLOW}📩 Creating email notification channel...${RESET}"

CHANNEL_ID=$(gcloud alpha monitoring channels create \
  --type=email \
  --display-name="Uptime Email Alerts" \
  --channel-labels=email_address=$EMAIL \
  --format="value(name)" \
  2>/dev/null)

if [[ -z "$CHANNEL_ID" ]]; then
  echo -e "${RED}❌ Failed to create notification channel.${RESET}"
  exit 1
else
  echo -e "${GREEN}✅ Notification Channel Created: $CHANNEL_ID${RESET}"
fi

# === 2. Create Uptime Check ===
echo -e "${YELLOW}🌐 Creating uptime check...${RESET}"

UPTIME_CHECK_ID=$(gcloud monitoring uptime create \
  --display-name=$CHECK_NAME \
  --host=$URL \
  --path="/" \
  --port=80 \
  --period="300s" \
  --timeout="10s" \
  --format="value(name)" \
  2>/dev/null)

if [[ -z "$UPTIME_CHECK_ID" ]]; then
  echo -e "${RED}❌ Failed to create uptime check.${RESET}"
  exit 1
else
  echo -e "${GREEN}✅ Uptime Check Created: $UPTIME_CHECK_ID${RESET}"
fi

# === 3. Create Alert Policy JSON ===
echo -e "${YELLOW}📝 Generating alert policy json...${RESET}"

cat > policy.json <<EOF
{
  "displayName": "Uptime Failure Alert",
  "enabled": true,
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "Uptime Check Failed",
      "conditionThreshold": {
        "filter": "metric.type=\\"monitoring.googleapis.com/uptime_check/check_passed\\" AND resource.type=\\"uptime_url\\" AND metric.label.check_id=\\"$UPTIME_CHECK_ID\\"",
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

echo -e "${GREEN}✅ policy.json created successfully.${RESET}"

# === 4. Create Alert Policy ===
echo -e "${YELLOW}🚨 Creating alert policy...${RESET}"

gcloud alpha monitoring policies create --policy-from-file=policy.json 2>/dev/null

if [[ $? -ne 0 ]]; then
  echo -e "${RED}❌ Failed to create alert policy.${RESET}"
  exit 1
else
  echo -e "${GREEN}✅ Alert Policy Created Successfully!${RESET}"
fi

# === 5. Done ===
echo -e "${GREEN}🎉 Monitoring setup completed successfully!${RESET}"
echo -e "${GREEN}✅ Uptime Check: $UPTIME_CHECK_ID${RESET}"
echo -e "${GREEN}✅ Alert Policy Active${RESET}"
echo -e "${GREEN}✅ Alerts will be sent to: $EMAIL${RESET}"


