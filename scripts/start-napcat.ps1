param(
  [switch]$ResetExistingQQ,
  [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$sourceNapcatDir = Join-Path $root '.runtime\NapCatQQ'
$deployNapcatDir = Join-Path $env:LOCALAPPDATA 'CodexNapCatQQ'
$qqInstallDir = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Tencent\QQNT' -ErrorAction SilentlyContinue).Install
$envFile = Join-Path $root '.env'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

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

function Get-QuickLoginUin {
  $envMap = Read-EnvMap $envFile
  $configuredUin = [string]$envMap['NAPCAT_QUICK_LOGIN_UIN']
  if ($configuredUin -match '^\d+$') {
    return $configuredUin
  }

  $configDir = Join-Path $deployNapcatDir 'config'
  if (!(Test-Path $configDir)) {
    return ''
  }

  $detectedFile = Get-ChildItem $configDir -Filter 'napcat_*.json' -ErrorAction SilentlyContinue |
    Where-Object { $_.BaseName -match '^napcat_(\d+)$' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

  if ($detectedFile -and $detectedFile.BaseName -match '^napcat_(\d+)$') {
    return $matches[1]
  }

  return ''
}

function Test-PortListening {
  param(
    [int]$Port
  )

  $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
  return $null -ne $connection
}

function Wait-PortListening {
  param(
    [int]$Port,
    [int]$TimeoutSeconds
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-PortListening -Port $Port) {
      return $true
    }

    Start-Sleep -Seconds 1
  }

  return (Test-PortListening -Port $Port)
}

function Stop-ExistingNapCatProcesses {
  foreach ($imageName in @('QQ.exe', 'NapCatWinBootMain.exe')) {
    try {
      & taskkill /F /T /IM $imageName *> $null
    } catch {
      continue
    }
  }
}

if (!$qqInstallDir) {
  $qqUninstall = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\QQ').UninstallString
  $qqInstallDir = (Split-Path (($qqUninstall -replace '"', '') -replace '\\\\', '\') -Parent)
}

$qqPath = Join-Path $qqInstallDir 'QQ.exe'

if (!(Test-Path $sourceNapcatDir)) {
  throw "NapCat directory not found: $sourceNapcatDir"
}

if (!(Test-Path $qqPath)) {
  throw "QQ executable not found: $qqPath"
}

if (Test-PortListening -Port 3000) {
  Write-Output 'NapCat OneBot HTTP is already listening on 127.0.0.1:3000. Skipping a duplicate start.'
  exit 0
}

if ($ResetExistingQQ) {
  Write-Output 'Restarting existing QQ/NapCat processes to recover OneBot HTTP.'
  Stop-ExistingNapCatProcesses
  Start-Sleep -Seconds 2
}

if ((Test-PortListening -Port 6099) -and -not $ResetExistingQQ) {
  throw 'NapCat WebUI is already listening on 127.0.0.1:6099, but OneBot HTTP on 127.0.0.1:3000 is unavailable.'
}

New-Item -ItemType Directory -Force -Path $deployNapcatDir | Out-Null

robocopy $sourceNapcatDir $deployNapcatDir /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -gt 7) {
  throw "Failed to sync NapCat runtime. robocopy exit code: $LASTEXITCODE"
}

$mainPath = Join-Path $deployNapcatDir 'napcat.mjs'
$loadPath = Join-Path $deployNapcatDir 'loadNapCat.js'
$injectPath = Join-Path $deployNapcatDir 'NapCatWinBootHook.dll'
$launcherPath = Join-Path $deployNapcatDir 'NapCatWinBootMain.exe'

$env:NAPCAT_PATCH_PACKAGE = Join-Path $deployNapcatDir 'qqnt.json'
$env:NAPCAT_LOAD_PATH = $loadPath
$env:NAPCAT_INJECT_PATH = $injectPath
$env:NAPCAT_LAUNCHER_PATH = $launcherPath
$env:NAPCAT_MAIN_PATH = $mainPath
$env:NAPCAT_WORKDIR = $deployNapcatDir

$mainUrl = $mainPath -replace '\\', '/'
$loadContent = @"
(async () => {await import("file:///$mainUrl")})()
"@
[System.IO.File]::WriteAllText($loadPath, $loadContent, $utf8NoBom)

$argumentList = @($qqPath, $injectPath)
$quickLoginUin = Get-QuickLoginUin
if ($quickLoginUin) {
  $argumentList += @('-q', $quickLoginUin)
  Write-Output "Using NapCat quick login account: $quickLoginUin"
}

Start-Process -FilePath $launcherPath -ArgumentList $argumentList -WorkingDirectory $deployNapcatDir

if (!(Wait-PortListening -Port 3000 -TimeoutSeconds $TimeoutSeconds)) {
  if (Test-PortListening -Port 6099) {
    throw 'NapCat WebUI started, but OneBot HTTP on 127.0.0.1:3000 did not become ready.'
  }

  throw 'NapCat did not start OneBot HTTP on 127.0.0.1:3000 within the expected time.'
}

Write-Output 'NapCat OneBot HTTP is listening on 127.0.0.1:3000.'
