$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$napcatDeployDir = Join-Path $env:LOCALAPPDATA 'CodexNapCatQQ'

function Get-NpmCommandPath {
  $npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if ($npmCommand) {
    return $npmCommand.Source
  }

  $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($nodeCommand) {
    $candidate = Join-Path (Split-Path $nodeCommand.Source -Parent) 'npm.cmd'
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  foreach ($candidate in @(
    'D:\npm.cmd',
    (Join-Path $env:ProgramFiles 'nodejs\npm.cmd'),
    (Join-Path ${env:ProgramFiles(x86)} 'nodejs\npm.cmd')
  )) {
    if ($candidate -and (Test-Path $candidate)) {
      return $candidate
    }
  }

  throw 'npm.cmd was not found.'
}

function Get-WebUiCredential {
  $configCandidates = @(
    (Join-Path $napcatDeployDir 'webui.json'),
    (Join-Path $napcatDeployDir 'config\webui.json')
  )

  $webUiConfigPath = $configCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (!$webUiConfigPath) {
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

function Get-LoginHint {
  try {
    $credential = Get-WebUiCredential
    if (!$credential) {
      return $null
    }

    $status = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:6099/api/QQLogin/CheckLoginStatus' -Headers @{ Authorization = "Bearer $credential" }
    if ($status.code -ne 0 -or !$status.data) {
      return $null
    }

    if ($status.data.isLogin) {
      return 'QQ is logged in, but OneBot HTTP on port 3000 is still unavailable. Check the NapCat config.'
    }

    if (![string]::IsNullOrWhiteSpace([string]$status.data.qrcodeurl)) {
      return "QQ login is still pending. Scan the QR code: $($status.data.qrcodeurl)"
    }

    if (![string]::IsNullOrWhiteSpace([string]$status.data.loginError)) {
      return "QQ login is still pending. Current status: $($status.data.loginError)"
    }
  } catch {
    return $null
  }

  return $null
}

function Test-PortListening {
  param(
    [int]$Port
  )

  $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
  return $null -ne $connection
}

if (!(Test-PortListening -Port 3000)) {
  & (Join-Path $PSScriptRoot 'start-napcat.ps1')

  $deadline = (Get-Date).AddSeconds(25)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 1
    if (Test-PortListening -Port 3000) {
      break
    }
  }
}

if (!(Test-PortListening -Port 3000)) {
  $loginHint = Get-LoginHint
  if ($loginHint) {
    throw "NapCat HTTP server did not start on 127.0.0.1:3000. $loginHint"
  }

  throw 'NapCat HTTP server did not start on 127.0.0.1:3000. QQ login may still be required.'
}

Push-Location $root
try {
  $npmPath = Get-NpmCommandPath
  & $npmPath run run
} finally {
  Pop-Location
}
