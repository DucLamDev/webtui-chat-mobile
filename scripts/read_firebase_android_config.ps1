param(
  [Parameter(Mandatory = $true)]
  [string]$GoogleServicesJson
)

$ErrorActionPreference = 'Stop'
$configPath = (Resolve-Path -LiteralPath $GoogleServicesJson).Path
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$client = $config.client | Where-Object {
  $_.client_info.android_client_info.package_name -eq 'com.vpsttt.webtui_chat'
} | Select-Object -First 1
if ($null -eq $client) {
  throw 'google-services.json does not contain package com.vpsttt.webtui_chat.'
}

$projectId = [string]$config.project_info.project_id
$senderId = [string]$config.project_info.project_number
$appId = [string]$client.client_info.mobilesdk_app_id
$apiKey = [string]($client.api_key | Select-Object -First 1).current_key
if ($projectId -ne 'webtui-chat') { throw "Unexpected Firebase project_id: $projectId" }
if ($senderId -ne '595077870179') { throw "Unexpected Firebase project_number: $senderId" }
if ($appId -ne '1:595077870179:android:a6f4ff5cc14a0d1485be56') {
  throw "Unexpected Firebase Android app ID: $appId"
}
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'Firebase api_key.current_key is missing.' }

Write-Output "MOBILE_FIREBASE_API_KEY=$apiKey"
Write-Output "MOBILE_FIREBASE_MESSAGING_SENDER_ID=$senderId"
Write-Output "MOBILE_FIREBASE_PROJECT_ID=$projectId"
Write-Output "MOBILE_FIREBASE_ANDROID_APP_ID=$appId"
Write-Output 'MOBILE_FIREBASE_IOS_APP_ID='
