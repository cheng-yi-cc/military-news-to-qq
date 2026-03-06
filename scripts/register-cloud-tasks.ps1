param(
  [string]$TaskPrefix = 'MilitaryDigest',
  [string]$DailyTime = '08:30'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$powerShellPath = (Get-Command powershell.exe).Source
$startScript = Join-Path $PSScriptRoot 'start-napcat.ps1'
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

$startAction = New-ScheduledTaskAction `
  -Execute $powerShellPath `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`"" `
  -WorkingDirectory $root

$dailyAction = New-ScheduledTaskAction `
  -Execute $powerShellPath `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$dailyScript`"" `
  -WorkingDirectory $root

$startTrigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$dailyTrigger = New-ScheduledTaskTrigger -Daily -At $dailyAt

$startTaskName = "$TaskPrefix NapCat Startup"
$dailyTaskName = "$TaskPrefix Daily Digest"

Register-ScheduledTask `
  -TaskName $startTaskName `
  -Description 'Starts QQ and NapCat for the military digest sender after user logon.' `
  -Action $startAction `
  -Trigger $startTrigger `
  -Principal $principal `
  -Settings $settings `
  -Force | Out-Null

Register-ScheduledTask `
  -TaskName $dailyTaskName `
  -Description "Runs the daily military digest sender at $DailyTime local time." `
  -Action $dailyAction `
  -Trigger $dailyTrigger `
  -Principal $principal `
  -Settings $settings `
  -Force | Out-Null

Write-Output "Registered scheduled tasks for $currentUser"
Write-Output "  $startTaskName"
Write-Output "  $dailyTaskName"
