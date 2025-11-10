#!/bin/bash

# Variables
UPTIME_NAME="gke-rest-api-products"
PROJECT_ID="my-project-app-477009"
HOST="34.133.250.137"
PATH="/products"
CHECKER_ZONE="us-central1-a"
PERIOD=300     # allowed: 60, 300, 600, 900, 3600
TIMEOUT=10    # timeout seconds

echo "Creating uptime check: $UPTIME_NAME"

gcloud monitoring uptime create "$UPTIME_NAME" \
  --project="$PROJECT_ID" \
  --host="$HOST" \
  --path="$PATH" \
  --checker-zone="$CHECKER_ZONE" \
  --period="$PERIOD" \
  --timeout="$TIMEOUT" \
  --http


echo "All done."
