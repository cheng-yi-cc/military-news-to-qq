$ErrorActionPreference = 'Stop'

$napcatDeployDir = Join-Path $env:LOCALAPPDATA 'CodexNapCatQQ'
$qrCodePath = Join-Path $napcatDeployDir 'cache\qrcode.png'

function Test-PortListening {
  param(
    [int]$Port
  )

  $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
  return $null -ne $connection
}

function Get-WebUiCredential {
  $webUiConfigPath = Join-Path $napcatDeployDir 'config\webui.json'
  if (!(Test-Path $webUiConfigPath)) {
    return $null
  }

  $webUiConfig = Get-Content -Raw $webUiConfigPath | ConvertFrom-Json
  $token = [string]$webUiConfig.token
  if ([string]::IsNullOrWhiteSpace($token)) {
    return $null
  }

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($token + '.napcat')
    $hash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }

  $body = @{ hash = $hash } | ConvertTo-Json
  $login = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:6099/api/auth/login' -ContentType 'application/json' -Body $body
  return $login.data.Credential
}

function Invoke-WebUiPost {
  param(
    [string]$Credential,
    [string]$Path
  )

  return Invoke-RestMethod -Method Post -Uri ("http://127.0.0.1:6099/api" + $Path) -Headers @{ Authorization = "Bearer $Credential" }
}

if (!(Test-PortListening -Port 6099)) {
  & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'start-napcat.ps1')

  $deadline = (Get-Date).AddSeconds(20)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 1
    if (Test-PortListening -Port 6099) {
      break
    }
  }
}

if (!(Test-PortListening -Port 6099)) {
  throw 'NapCat WebUI did not start on 127.0.0.1:6099.'
}

$credential = Get-WebUiCredential
if (!$credential) {
  throw 'Could not get a WebUI credential from NapCat.'
}

$status = Invoke-WebUiPost -Credential $credential -Path '/QQLogin/CheckLoginStatus'
if ($status.code -ne 0 -or !$status.data) {
  throw "Unexpected NapCat login status response: $($status | ConvertTo-Json -Depth 6)"
}

$ob11Ready = Test-PortListening -Port 3000
if ($status.data.isLogin) {
  Write-Output 'QQ login: OK'
  Write-Output ("OneBot HTTP (3000): " + ($(if ($ob11Ready) { 'OK' } else { 'NOT READY' })))
  exit 0
}

$freshQrCodeUrl = $null
if (-not $status.data.isLogin) {
  Invoke-WebUiPost -Credential $credential -Path '/QQLogin/RefreshQRcode' | Out-Null
  Start-Sleep -Seconds 1
  $qrPayload = Invoke-WebUiPost -Credential $credential -Path '/QQLogin/GetQQLoginQrcode'
  if ($qrPayload.code -eq 0 -and $qrPayload.data) {
    $freshQrCodeUrl = [string]$qrPayload.data.qrcode
  }

  Start-Sleep -Seconds 1
  $status = Invoke-WebUiPost -Credential $credential -Path '/QQLogin/CheckLoginStatus'
}

Write-Output 'QQ login: PENDING'
Write-Output ("OneBot HTTP (3000): " + ($(if ($ob11Ready) { 'OK' } else { 'NOT READY' })))
if (Test-Path $qrCodePath) {
  Write-Output ("QR file: " + $qrCodePath)
  Start-Process $qrCodePath
}
if (![string]::IsNullOrWhiteSpace($freshQrCodeUrl)) {
  Write-Output ("QR code: " + $freshQrCodeUrl)
} elseif (![string]::IsNullOrWhiteSpace([string]$status.data.qrcodeurl)) {
  Write-Output ("QR code: " + $status.data.qrcodeurl)
}
if (![string]::IsNullOrWhiteSpace([string]$status.data.loginError)) {
  Write-Output ("Login status: " + $status.data.loginError)
}
