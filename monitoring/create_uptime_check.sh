# === CONFIG ===
$ProjectID = "my-project-app-477009"
$Email = "mallelajahnavi123@gmail.com"
$APIHost = "34.133.250.137"
$Endpoints = @("/products", "/products/1")   # Add more if needed
$CheckPeriod = 5                             # in minutes
$Timeout = 10                                # in seconds

# === 1. Set project ===
Write-Host "Setting project..."
gcloud config set project $ProjectID

# === 2. Create Notification Channel ===
Write-Host "Creating notification channel..."
$ChannelID = gcloud alpha monitoring channels create `
    --type=email `
    --display-name "API Uptime Email Alerts" `
    --channel-labels email_address=$Email `
    --format="value(name)"

Write-Host "Notification Channel ID: $ChannelID"

# === 3. Create Uptime Checks and Alert Policies ===
foreach ($Path in $Endpoints) {
    $CheckName = "gke-rest-api-" + ($Path -replace '/','-')
    Write-Host "Creating uptime check for endpoint $Path ..."

    $UptimeCheckID = gcloud monitoring uptime create $CheckName `
        --synthetic-target=http `
        --host=$APIHost `
        --path=$Path `
        --port=80 `
        --period=$CheckPeriod `
        --timeout=$Timeout `
        --format="value(name)"

    Write-Host "Uptime Check created: $UptimeCheckID"

    # Create Alert Policy JSON
    $PolicyFile = "policy-$($CheckName).json"
    $AlertPolicy = @{
        displayName = "API Failure Alert - $Path"
        enabled = $true
        combiner = "OR"
        conditions = @(
            @{
                displayName = "API Endpoint $Path Failed"
                conditionThreshold = @{
                    filter = "metric.type=`"monitoring.googleapis.com/uptime_check/check_passed`" AND resource.type=`"uptime_url`" AND resource.label.check_id=`"$UptimeCheckID`""
                    comparison = "COMPARISON_LT"
                    thresholdValue = 1
                    duration = "0s"
                    trigger = @{ count = 1 }
                }
            }
        )
        notificationChannels = @($ChannelID)
    }

    $AlertPolicy | ConvertTo-Json -Depth 10 | Out-File $PolicyFile -Encoding UTF8

    Write-Host "Creating alert policy for $Path ..."
    gcloud alpha monitoring policies create --policy-from-file=$PolicyFile
    Write-Host "Alert policy created for $Path."
}

Write-Host "✅ All uptime checks and alerts created successfully!"
