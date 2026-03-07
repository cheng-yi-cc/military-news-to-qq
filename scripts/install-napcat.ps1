param(
  [switch]$Force,
  [string]$ReleaseTag = 'latest'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $root '.runtime\NapCatQQ'
$tmpDir = Join-Path $root '.tmp\napcat'
$envFile = Join-Path $root '.env'
$envExampleFile = Join-Path $root '.env.example'
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

function Set-EnvValue {
  param(
    [string]$Path,
    [string]$Key,
    [string]$Value
  )

  $lines = @()
  if (Test-Path $Path) {
    $lines = Get-Content $Path
  } elseif (Test-Path $envExampleFile) {
    $lines = Get-Content $envExampleFile
  }

  $pattern = '^\s*' + [regex]::Escape($Key) + '='
  $updated = $false

  for ($i = 0; $i -lt $lines.Count; $i += 1) {
    if ($lines[$i] -match $pattern) {
      $lines[$i] = "$Key=$Value"
      $updated = $true
    }
  }

  if (-not $updated) {
    $lines += "$Key=$Value"
  }

  [System.IO.File]::WriteAllText($Path, ($lines -join [Environment]::NewLine), $utf8NoBom)
}

function Write-Utf8NoBom {
  param(
    [string]$Path,
    [string]$Content
  )

  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Get-QQInstallDir {
  $qqInstallDir = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Tencent\QQNT' -ErrorAction SilentlyContinue).Install
  if ($qqInstallDir) {
    return $qqInstallDir
  }

  $qqUninstall = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\QQ' -ErrorAction SilentlyContinue).UninstallString
  if ($qqUninstall) {
    return Split-Path (($qqUninstall -replace '"', '') -replace '\\\\', '\') -Parent
  }

  throw 'QQ is not installed. Install QQ on the Windows host first.'
}

function Get-CurrentQQVersion {
  $qqInstallDir = Get-QQInstallDir
  $versionConfigPath = Join-Path $qqInstallDir 'versions\config.json'
  if (!(Test-Path $versionConfigPath)) {
    throw "Could not find QQ version config: $versionConfigPath"
  }

  $versionConfig = Get-Content -Raw $versionConfigPath | ConvertFrom-Json
  $version = [string]$versionConfig.curVersion
  if ([string]::IsNullOrWhiteSpace($version)) {
    throw "Could not read QQ version from $versionConfigPath"
  }

  return $version
}

function Get-DetectedQuickLoginUin {
  param(
    [string]$DeployDir
  )

  $configDir = Join-Path $DeployDir 'config'
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

function New-Token {
  return [guid]::NewGuid().ToString('N')
}

if (!(Test-Path $envFile)) {
  if (Test-Path $envExampleFile) {
    Copy-Item $envExampleFile $envFile
  } else {
    throw "Missing env file: $envFile"
  }
}

$envMap = Read-EnvMap $envFile
$webUiToken = $envMap['NAPCAT_WEBUI_TOKEN']
$oneBotToken = $envMap['QQ_API_ACCESS_TOKEN']
$baseUrlValue = $envMap['QQ_API_BASE_URL']
$quickLoginUin = $envMap['NAPCAT_QUICK_LOGIN_UIN']

if ([string]::IsNullOrWhiteSpace($baseUrlValue)) {
  $baseUrlValue = 'http://127.0.0.1:3000'
  Set-EnvValue -Path $envFile -Key 'QQ_API_BASE_URL' -Value $baseUrlValue
}

if ([string]::IsNullOrWhiteSpace($oneBotToken)) {
  $oneBotToken = New-Token
  Set-EnvValue -Path $envFile -Key 'QQ_API_ACCESS_TOKEN' -Value $oneBotToken
}

if ([string]::IsNullOrWhiteSpace($webUiToken)) {
  $webUiToken = New-Token
  Set-EnvValue -Path $envFile -Key 'NAPCAT_WEBUI_TOKEN' -Value $webUiToken
}

if ([string]::IsNullOrWhiteSpace($quickLoginUin)) {
  $quickLoginUin = Get-DetectedQuickLoginUin -DeployDir (Join-Path $env:LOCALAPPDATA 'CodexNapCatQQ')
  if ($quickLoginUin) {
    Set-EnvValue -Path $envFile -Key 'NAPCAT_QUICK_LOGIN_UIN' -Value $quickLoginUin
  }
}

$baseUri = [Uri]$baseUrlValue
$qqVersion = Get-CurrentQQVersion
$buildVersion = $qqVersion.Split('-')[-1]
$releaseApiUrl =
  if ($ReleaseTag -eq 'latest') {
    'https://api.github.com/repos/NapNeko/NapCatQQ/releases/latest'
  } else {
    "https://api.github.com/repos/NapNeko/NapCatQQ/releases/tags/$ReleaseTag"
  }

$headers = @{
  Accept = 'application/vnd.github+json'
  'User-Agent' = 'military-news-to-qq'
}

$downloadRequired = $Force -or !(Test-Path (Join-Path $runtimeDir 'napcat.mjs'))
if ($downloadRequired) {
  New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
  $release = Invoke-RestMethod -Headers $headers -Uri $releaseApiUrl
  $asset = $release.assets | Where-Object { $_.name -eq 'NapCat.Shell.zip' } | Select-Object -First 1
  if (!$asset) {
    throw "NapCat release '$($release.tag_name)' does not include NapCat.Shell.zip"
  }

  $zipPath = Join-Path $tmpDir 'NapCat.Shell.zip'
  Invoke-WebRequest -Headers $headers -Uri $asset.browser_download_url -OutFile $zipPath

  if (Test-Path $runtimeDir) {
    Remove-Item -Recurse -Force $runtimeDir
  }

  New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
  Expand-Archive -Path $zipPath -DestinationPath $runtimeDir -Force
}

$mainPath = Join-Path $runtimeDir 'napcat.mjs'
if (!(Test-Path $mainPath)) {
  $nestedRuntimeDir = Get-ChildItem $runtimeDir -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName 'napcat.mjs')
  } | Select-Object -First 1

  if ($nestedRuntimeDir) {
    robocopy $nestedRuntimeDir.FullName $runtimeDir /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -gt 7) {
      throw "Failed to flatten NapCat runtime. robocopy exit code: $LASTEXITCODE"
    }

    Remove-Item -Recurse -Force $nestedRuntimeDir.FullName
  }
}

if (!(Test-Path $mainPath)) {
  throw "NapCat runtime is incomplete: $mainPath"
}

$qqntPath = Join-Path $runtimeDir 'qqnt.json'
$qqntConfig = Get-Content -Raw $qqntPath | ConvertFrom-Json
$qqntConfig.version = $qqVersion
$qqntConfig.buildVersion = $buildVersion
if ([string]$qqntConfig.linuxVersion -match '^(.*)-\d+$') {
  $qqntConfig.linuxVersion = "$($matches[1])-$buildVersion"
}
$qqntConfig.main = './loadNapCat.js'
Write-Utf8NoBom -Path $qqntPath -Content ($qqntConfig | ConvertTo-Json -Depth 20)

$configDir = Join-Path $runtimeDir 'config'
New-Item -ItemType Directory -Force -Path $configDir | Out-Null

$webUiConfig = @{
  host = '127.0.0.1'
  port = 6099
  token = $webUiToken
  loginRate = 10
  autoLoginAccount = $quickLoginUin
  theme = @{
    fontMode = 'system'
    dark = @{}
    light = @{}
  }
  disableWebUI = $false
  accessControlMode = 'none'
  ipWhitelist = @()
  ipBlacklist = @()
  enableXForwardedFor = $false
}

$oneBotConfig = @{
  network = @{
    httpServers = @(
      @{
        name = 'codex_http_server'
        enable = $true
        host = $baseUri.Host
        port = $baseUri.Port
        enableCors = $false
        enableWebsocket = $false
        messagePostFormat = 'array'
        token = $oneBotToken
        debug = $false
      }
    )
    httpSseServers = @()
    httpClients = @()
    websocketServers = @()
    websocketClients = @()
    plugins = @()
  }
  musicSignUrl = ''
  enableLocalFile2Url = $false
  parseMultMsg = $false
  imageDownloadProxy = ''
}

Write-Utf8NoBom -Path (Join-Path $configDir 'webui.json') -Content ($webUiConfig | ConvertTo-Json -Depth 20)
Write-Utf8NoBom -Path (Join-Path $configDir 'onebot11.json') -Content ($oneBotConfig | ConvertTo-Json -Depth 20)
Write-Utf8NoBom -Path (Join-Path $runtimeDir 'webui.json') -Content ($webUiConfig | ConvertTo-Json -Depth 20)
Write-Utf8NoBom -Path (Join-Path $runtimeDir 'onebot11.json') -Content ($oneBotConfig | ConvertTo-Json -Depth 20)

Write-Output "NapCat runtime prepared at $runtimeDir"
Write-Output "QQ version pinned to $qqVersion"
Write-Output "WebUI: http://127.0.0.1:6099"
Write-Output "OneBot HTTP: $baseUrlValue"
