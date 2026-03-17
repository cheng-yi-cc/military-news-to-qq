param(
  [string]$TaskPrefix = 'MilitaryDigest',
  [string]$DailyTime = '08:30'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$powerShellPath = (Get-Command powershell.exe).Source
$dailyScript = Join-Path $PSScriptRoot 'run-daily.ps1'
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).
  IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

try {
  $dailyAt = [datetime]::ParseExact($DailyTime, 'HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
} catch {
  throw "Invalid DailyTime '$DailyTime'. Use HH:mm, for example 08:30."
}

$runLevel = if ($isAdmin) { 'Highest' } else { 'Limited' }
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel $runLevel
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -RunOnlyIfNetworkAvailable `
  -StartWhenAvailable `
  -MultipleInstances IgnoreNew `
  -ExecutionTimeLimit (New-TimeSpan -Hours 2)

$dailyAction = New-ScheduledTaskAction `
  -Execute $powerShellPath `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$dailyScript`"" `
  -WorkingDirectory $root

$dailyTrigger = New-ScheduledTaskTrigger -Daily -At $dailyAt

$dailyTaskName = "$TaskPrefix Daily Digest"

$legacyStartTaskName = "$TaskPrefix NapCat Startup"
$legacyTask = Get-ScheduledTask -TaskName $legacyStartTaskName -ErrorAction SilentlyContinue
if ($legacyTask) {
  Unregister-ScheduledTask -TaskName $legacyStartTaskName -Confirm:$false
  Write-Output "Removed legacy logon task: $legacyStartTaskName"
}

Register-ScheduledTask `
  -TaskName $dailyTaskName `
  -Description "Runs the daily military digest sender at $DailyTime local time and starts QQ/NapCat on demand." `
  -Action $dailyAction `
  -Trigger $dailyTrigger `
  -Principal $principal `
  -Settings $settings `
  -Force | Out-Null

Write-Output "Registered scheduled tasks for $currentUser"
Write-Output "  $dailyTaskName"
