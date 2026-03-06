param(
  [string]$TaskPrefix = 'MilitaryDigest'
)

$ErrorActionPreference = 'Stop'

$taskNames = @(
  "$TaskPrefix NapCat Startup",
  "$TaskPrefix Daily Digest"
)

foreach ($taskName in $taskNames) {
  $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if ($task) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Output "Removed scheduled task: $taskName"
  } else {
    Write-Output "Scheduled task not found: $taskName"
  }
}
