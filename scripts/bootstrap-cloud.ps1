param(
  [string]$DailyTime = ''
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root '.env'
$envExampleFile = Join-Path $root '.env.example'

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

function Read-EnvMap {
  param(
    [string]$Path
  )

  $map = @{}
  if (!(Test-Path $Path)) {
    return $map
  }

  foreach ($line in Get-Content $Path) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
      continue
    }

    $parts = $line -split '=', 2
    if ($parts.Length -ne 2) {
      continue
    }

    $map[$parts[0].Trim()] = $parts[1]
  }

  return $map
}

if (!(Test-Path $envFile)) {
  if (!(Test-Path $envExampleFile)) {
    throw "Missing env template: $envExampleFile"
  }

  Copy-Item $envExampleFile $envFile
  throw "Created $envFile from .env.example. Fill in the required values and run bootstrap again."
}

$envMap = Read-EnvMap $envFile
$provider = [string]$envMap['LLM_PROVIDER']
if ([string]::IsNullOrWhiteSpace($provider)) {
  $provider = 'openai'
}

$missing = @()
if ([string]::IsNullOrWhiteSpace([string]$envMap['QQ_GROUP_ID'])) {
  $missing += 'QQ_GROUP_ID'
}

if ($provider -eq 'deepseek') {
  if ([string]::IsNullOrWhiteSpace([string]$envMap['DEEPSEEK_API_KEY'])) {
    $missing += 'DEEPSEEK_API_KEY'
  }
} elseif ([string]::IsNullOrWhiteSpace([string]$envMap['OPENAI_API_KEY'])) {
  $missing += 'OPENAI_API_KEY'
}

if ($missing.Count -gt 0) {
  throw "Missing required values in .env: $($missing -join ', ')"
}

if ([string]::IsNullOrWhiteSpace($DailyTime)) {
  $DailyTime = [string]$envMap['CLOUD_DAILY_TIME']
}

if ([string]::IsNullOrWhiteSpace($DailyTime)) {
  $DailyTime = '08:30'
}

Push-Location $root
try {
  $npmPath = Get-NpmCommandPath
  & $npmPath ci
} finally {
  Pop-Location
}

& (Join-Path $PSScriptRoot 'install-napcat.ps1')
& (Join-Path $PSScriptRoot 'register-cloud-tasks.ps1') -DailyTime $DailyTime

Write-Output ''
Write-Output 'Cloud bootstrap complete.'
Write-Output "Daily send time: $DailyTime"
Write-Output 'Next steps:'
Write-Output '  1. Run npm.cmd run qq:status and scan the QR code once.'
Write-Output '  2. Enable Windows auto-logon for this account.'
Write-Output '  3. Disconnect the RDP session without signing out.'
