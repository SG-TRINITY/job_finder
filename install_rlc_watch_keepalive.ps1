Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ControlScript = Join-Path $Root "rlc_watch_control.ps1"
$HiddenLauncher = Join-Path $Root "run_keepalive_hidden.vbs"
$TaskName = "RLC Watch Keepalive"

if (-not (Test-Path -LiteralPath $ControlScript)) {
    throw "Missing $ControlScript"
}

if (-not (Test-Path -LiteralPath $HiddenLauncher)) {
    throw "Missing $HiddenLauncher"
}

# WScript has no console window, and launches PowerShell hidden from creation.
$wscriptExe = Join-Path $env:SystemRoot "System32\wscript.exe"
$actionArgs = '//B //Nologo "' + $HiddenLauncher + '"'
$action = New-ScheduledTaskAction -Execute $wscriptExe -Argument $actionArgs -WorkingDirectory $Root

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
