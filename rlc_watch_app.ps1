param(
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$WatcherScript = Join-Path $Root "run_watcher.cmd"
$LogFile = Join-Path $Root "logs\rlc-watch.log"
$AppLogFile = Join-Path $Root "logs\rlc-watch-app.log"
$SettingsFile = Join-Path $Root "local_settings.json"
$PythonExe = "C:\Python313\python.exe"

function Write-AppLog([string]$Message) {
    $logDir = Split-Path -Parent $AppLogFile
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -LiteralPath $AppLogFile -Value "[$stamp] $Message"
}

trap {
    Write-AppLog "Unhandled error: $($_.Exception.Message)"
    continue
}

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

    if ($watchdog -and $scraper) {
        return @{
            Running = $true
            Text = "Running"
            Detail = "Watchdog and scraper are active."
            ProcessCount = $processes.Count
        }
    }
    if ($scraper) {
        return @{
            Running = $true
            Text = "Running without watchdog"
            Detail = "Scraper is active, but the watchdog is not."
            ProcessCount = $processes.Count
        }
    }
    return @{
        Running = $false
        Text = "Stopped"
        Detail = "No watcher process is running."
        ProcessCount = 0
    }
}

function Start-RlcWatcher {
    if ((Get-RlcStatus).Running) {
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

function Open-PathIfExists([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Start-Process -FilePath $Path | Out-Null
    }
}

function Get-LastLogLine {
    if (-not (Test-Path -LiteralPath $LogFile)) {
        return "Log file has not been created yet."
    }

    $line = Get-Content -LiteralPath $LogFile -Tail 1 -ErrorAction SilentlyContinue
    if ($line) {
        return $line
    }
    return "Log file is empty."
}

if ($SelfTest) {
    $status = Get-RlcStatus
    Write-Host "Self-test ok. Status: $($status.Text)"
    exit 0
}

Write-AppLog "Controller starting"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = "Ladle Me Jobs"
$form.Size = New-Object System.Drawing.Size(420, 260)
$form.StartPosition = "CenterScreen"
$form.MaximizeBox = $false
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "Ladle Me Jobs"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(20, 18)
$form.Controls.Add($titleLabel)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$statusLabel.AutoSize = $true
$statusLabel.Location = New-Object System.Drawing.Point(22, 66)
$form.Controls.Add($statusLabel)

$detailLabel = New-Object System.Windows.Forms.Label
$detailLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$detailLabel.Size = New-Object System.Drawing.Size(360, 42)
$detailLabel.Location = New-Object System.Drawing.Point(24, 96)
$form.Controls.Add($detailLabel)

$logLabel = New-Object System.Windows.Forms.Label
$logLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$logLabel.Size = New-Object System.Drawing.Size(360, 35)
$logLabel.Location = New-Object System.Drawing.Point(24, 138)
$form.Controls.Add($logLabel)

$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = "Start Watcher"
$startButton.Size = New-Object System.Drawing.Size(115, 32)
$startButton.Location = New-Object System.Drawing.Point(24, 180)
$form.Controls.Add($startButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = "Stop Watcher"
$stopButton.Size = New-Object System.Drawing.Size(115, 32)
$stopButton.Location = New-Object System.Drawing.Point(148, 180)
$form.Controls.Add($stopButton)

$logButton = New-Object System.Windows.Forms.Button
$logButton.Text = "Open Log"
$logButton.Size = New-Object System.Drawing.Size(95, 32)
$logButton.Location = New-Object System.Drawing.Point(272, 180)
$form.Controls.Add($logButton)

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$showMenuItem = $trayMenu.Items.Add("Show Ladle Me Jobs")
$startMenuItem = $trayMenu.Items.Add("Start Watcher")
$stopMenuItem = $trayMenu.Items.Add("Stop Watcher")
[void]$trayMenu.Items.Add("-")
$openLogMenuItem = $trayMenu.Items.Add("Open Log")
$openSettingsMenuItem = $trayMenu.Items.Add("Open Settings")
[void]$trayMenu.Items.Add("-")
$exitMenuItem = $trayMenu.Items.Add("Exit App")

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
$notifyIcon.Text = "Ladle Me Jobs"
$notifyIcon.ContextMenuStrip = $trayMenu
$notifyIcon.Visible = $true

$script:AllowExit = $false

function Refresh-Ui {
    try {
        $status = Get-RlcStatus
        if ($status.Running) {
            $statusLabel.ForeColor = [System.Drawing.Color]::ForestGreen
            $notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
        } else {
            $statusLabel.ForeColor = [System.Drawing.Color]::Firebrick
            $notifyIcon.Icon = [System.Drawing.SystemIcons]::Warning
        }

        $statusLabel.Text = "Status: $($status.Text)"
        $detailLabel.Text = "$($status.Detail) Process count: $($status.ProcessCount)."
        $logLabel.Text = "Latest log: $(Get-LastLogLine)"
        $notifyIcon.Text = "Ladle Me Jobs - $($status.Text)"

        $startButton.Enabled = -not $status.Running
        $startMenuItem.Enabled = -not $status.Running
        $stopButton.Enabled = $status.Running
        $stopMenuItem.Enabled = $status.Running
    } catch {
        Write-AppLog "Refresh error: $($_.Exception.Message)"
    }
}

$startAction = {
    try {
        Start-RlcWatcher
        Start-Sleep -Milliseconds 600
        Refresh-Ui
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Could not start watcher") | Out-Null
    }
}

$stopAction = {
    Stop-RlcWatcher
    Start-Sleep -Milliseconds 600
    Refresh-Ui
}

$showAction = {
    $form.Show()
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.Activate()
    Refresh-Ui
}

$exitAction = {
    $script:AllowExit = $true
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    $form.Close()
}

$startButton.Add_Click($startAction)
$startMenuItem.Add_Click($startAction)
$stopButton.Add_Click($stopAction)
$stopMenuItem.Add_Click($stopAction)
$logButton.Add_Click({ Open-PathIfExists $LogFile })
$openLogMenuItem.Add_Click({ Open-PathIfExists $LogFile })
$openSettingsMenuItem.Add_Click({ Open-PathIfExists $SettingsFile })
$showMenuItem.Add_Click($showAction)
$notifyIcon.Add_DoubleClick($showAction)
$exitMenuItem.Add_Click($exitAction)

$form.Add_FormClosing({
    param($sender, $eventArgs)
    if (-not $script:AllowExit) {
        $eventArgs.Cancel = $true
        $form.Hide()
        try {
            $notifyIcon.ShowBalloonTip(2000, "Ladle Me Jobs", "Still running in the tray.", [System.Windows.Forms.ToolTipIcon]::Info)
        } catch {
            Write-AppLog "Tray balloon error: $($_.Exception.Message)"
        }
    }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({ Refresh-Ui })
$timer.Start()

Refresh-Ui
try {
    [System.Windows.Forms.Application]::Run($form)
} finally {
    Write-AppLog "Controller stopped"
}
