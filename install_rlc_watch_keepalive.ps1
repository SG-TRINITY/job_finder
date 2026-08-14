Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ControlScript = Join-Path $Root "rlc_watch_control.ps1"
$TaskName = "RLC Watch Keepalive"

if (-not (Test-Path -LiteralPath $ControlScript)) {
    throw "Missing $ControlScript"
}

$powerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$actionArgs = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $ControlScript + '" Start'
$action = New-ScheduledTaskAction -Execute $powerShellExe -Argument $actionArgs -WorkingDirectory $Root

$startAt = (Get-Date).AddMinutes(1)
$trigger = New-ScheduledTaskTrigger `
    -Once `
    -At $startAt `
    -RepetitionInterval (New-TimeSpan -Minutes 15) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description "Starts the local RLC Watch watchdog if it is not already running." `
    -Force | Out-Null

Get-ScheduledTask -TaskName $TaskName |
    Select-Object TaskName,TaskPath,State |
    ConvertTo-Json -Compress
