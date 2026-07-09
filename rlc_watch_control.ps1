param(
    [ValidateSet('Status', 'Start', 'Stop')]
    [string]$Action = 'Status'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$WatcherScript = Join-Path $Root "run_watcher.cmd"
$LogFile = Join-Path $Root "logs\rlc-watch.log"

function Get-RlcProcesses {
    Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -and (
            $_.CommandLine -like "*scraper.py*--loop*" -or
            $_.CommandLine -like "*run_watcher.cmd*"
        )
    }
}

function Get-RlcStatus {
    $processes = @(Get-RlcProcesses)
    $watchdog = $processes | Where-Object { $_.CommandLine -like "*run_watcher.cmd*" }
    $scraper = $processes | Where-Object { $_.CommandLine -like "*scraper.py*--loop*" }
    $watchdogRunning = [bool]$watchdog
    $scraperRunning = [bool]$scraper

    if ($watchdogRunning -and $scraperRunning) {
        return @{
            running = $true
            watchdogRunning = $true
            scraperRunning = $true
            text = "Running"
            detail = "Watchdog and scraper are active."
            processCount = $processes.Count
        }
    }
    if ($scraperRunning) {
        return @{
            running = $true
            watchdogRunning = $false
            scraperRunning = $true
            text = "Running without watchdog"
            detail = "Scraper is active, but the watchdog is not."
            processCount = $processes.Count
        }
    }
    return @{
        running = $false
        watchdogRunning = $watchdogRunning
        scraperRunning = $false
        text = "Stopped"
        detail = "No watcher process is running."
        processCount = $processes.Count
    }
}

function Start-RlcWatcher {
    if ((Get-RlcStatus).running) {
        return
    }

    if (-not (Test-Path -LiteralPath $WatcherScript)) {
        throw "Missing $WatcherScript"
    }

    $logDir = Split-Path -Parent $LogFile
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }

    $cmdExe = Join-Path $env:SystemRoot "System32\cmd.exe"
    $taskRun = '/c ""' + $WatcherScript + '" >> "' + $LogFile + '" 2>&1"'
    Start-Process -FilePath $cmdExe -ArgumentList $taskRun -WorkingDirectory $Root -WindowStyle Hidden | Out-Null
}

function Stop-RlcWatcher {
    $processes = @(Get-RlcProcesses)
    foreach ($process in $processes) {
        try {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        } catch {
        }
    }
}

switch ($Action) {
    'Start' {
        Start-RlcWatcher
        Start-Sleep -Milliseconds 600
    }
    'Stop' {
        Stop-RlcWatcher
        Start-Sleep -Milliseconds 600
    }
}

Get-RlcStatus | ConvertTo-Json -Compress
