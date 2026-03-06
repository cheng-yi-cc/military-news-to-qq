$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$sourceNapcatDir = Join-Path $root '.runtime\NapCatQQ'
$deployNapcatDir = Join-Path $env:LOCALAPPDATA 'CodexNapCatQQ'
$qqInstallDir = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Tencent\QQNT' -ErrorAction SilentlyContinue).Install

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
Set-Content -Path $loadPath -Value $loadContent -Encoding UTF8

Start-Process -FilePath $launcherPath -ArgumentList @($qqPath, $injectPath) -WorkingDirectory $deployNapcatDir
