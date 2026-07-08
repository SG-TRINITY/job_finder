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

$Y2KColors = @{
    DeepInk = [System.Drawing.Color]::FromArgb(18, 12, 34)
    Night = [System.Drawing.Color]::FromArgb(31, 18, 58)
    Glass = [System.Drawing.Color]::FromArgb(41, 22, 73)
    ChromeLight = [System.Drawing.Color]::FromArgb(248, 247, 255)
    ChromeMid = [System.Drawing.Color]::FromArgb(176, 199, 255)
    ChromeDark = [System.Drawing.Color]::FromArgb(86, 66, 156)
    Aqua = [System.Drawing.Color]::FromArgb(77, 239, 255)
    Pink = [System.Drawing.Color]::FromArgb(255, 99, 213)
    Lavender = [System.Drawing.Color]::FromArgb(185, 142, 255)
    Lime = [System.Drawing.Color]::FromArgb(185, 255, 143)
    Text = [System.Drawing.Color]::FromArgb(252, 250, 255)
    Muted = [System.Drawing.Color]::FromArgb(215, 220, 255)
}

function Set-Y2KButton([System.Windows.Forms.Button]$Button, [System.Drawing.Color]$Accent) {
    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.UseVisualStyleBackColor = $false
    $Button.BackColor = $Y2KColors.Night
    $Button.ForeColor = $Y2KColors.Text
    $Button.Font = New-Object System.Drawing.Font("Lucida Console", 8, [System.Drawing.FontStyle]::Bold)
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Button.FlatAppearance.BorderColor = $Accent
    $Button.FlatAppearance.BorderSize = 1
    $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(72, 30, 108)
    $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(105, 45, 144)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Ladle Me Jobs"
$form.ClientSize = New-Object System.Drawing.Size(500, 315)
$form.StartPosition = "CenterScreen"
$form.MaximizeBox = $false
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.BackColor = $Y2KColors.DeepInk
$form.ForeColor = $Y2KColors.Text
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$form.Add_Paint({
    param($sender, $eventArgs)

    $graphics = $eventArgs.Graphics
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    $rect = $sender.ClientRectangle
    if ($rect.Width -le 0 -or $rect.Height -le 0) {
        return
    }

    $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $Y2KColors.DeepInk, $Y2KColors.Lavender, 35.0)
    try {
        $graphics.FillRectangle($bgBrush, $rect)
    } finally {
        $bgBrush.Dispose()
    }

    $gridPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(48, $Y2KColors.Aqua), 1)
    try {
        for ($x = -$rect.Height; $x -lt ($rect.Width + $rect.Height); $x += 22) {
            $graphics.DrawLine($gridPen, $x, $rect.Height, $x + 96, 138)
        }
        for ($y = 145; $y -lt $rect.Height; $y += 18) {
            $graphics.DrawLine($gridPen, 0, $y, $rect.Width, $y)
        }
    } finally {
        $gridPen.Dispose()
    }

    $headerRect = New-Object System.Drawing.Rectangle(14, 14, ($rect.Width - 28), 82)
    $headerBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($headerRect, $Y2KColors.ChromeLight, $Y2KColors.ChromeDark, 90.0)
    $headerPen = New-Object System.Drawing.Pen($Y2KColors.Aqua, 2)
    $shinePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(190, $Y2KColors.Pink), 1)
    try {
        $graphics.FillRectangle($headerBrush, $headerRect)
        $graphics.DrawRectangle($headerPen, $headerRect)
        $graphics.DrawLine($shinePen, 22, 28, ($rect.Width - 28), 76)
        $graphics.DrawLine($shinePen, 110, 22, ($rect.Width - 18), 58)
    } finally {
        $headerBrush.Dispose()
        $headerPen.Dispose()
        $shinePen.Dispose()
    }

    $panelRect = New-Object System.Drawing.Rectangle(16, 112, ($rect.Width - 32), 126)
    $panelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, $Y2KColors.Glass))
    $panelPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, $Y2KColors.Lavender), 1)
    try {
        $graphics.FillRectangle($panelBrush, $panelRect)
        $graphics.DrawRectangle($panelPen, $panelRect)
    } finally {
        $panelBrush.Dispose()
        $panelPen.Dispose()
    }

    $starPen = New-Object System.Drawing.Pen($Y2KColors.Text, 1)
    try {
        $graphics.DrawLine($starPen, 448, 26, 448, 42)
        $graphics.DrawLine($starPen, 440, 34, 456, 34)
        $graphics.DrawLine($starPen, 388, 72, 388, 84)
        $graphics.DrawLine($starPen, 382, 78, 394, 78)
    } finally {
        $starPen.Dispose()
    }
})

$eyebrowLabel = New-Object System.Windows.Forms.Label
$eyebrowLabel.Text = "RLC WATCH // Y2K JOB RADAR"
$eyebrowLabel.Font = New-Object System.Drawing.Font("Lucida Console", 8, [System.Drawing.FontStyle]::Bold)
$eyebrowLabel.ForeColor = $Y2KColors.Night
$eyebrowLabel.BackColor = [System.Drawing.Color]::Transparent
$eyebrowLabel.AutoSize = $true
$eyebrowLabel.Location = New-Object System.Drawing.Point(25, 24)
$form.Controls.Add($eyebrowLabel)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "Ladle Me Jobs"
$titleLabel.Font = New-Object System.Drawing.Font("Trebuchet MS", 24, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = $Y2KColors.Text
$titleLabel.BackColor = [System.Drawing.Color]::Transparent
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(23, 39)
$form.Controls.Add($titleLabel)

$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text = "chrome alerts for residence life postings"
$subtitleLabel.Font = New-Object System.Drawing.Font("Lucida Console", 8, [System.Drawing.FontStyle]::Regular)
$subtitleLabel.ForeColor = $Y2KColors.DeepInk
$subtitleLabel.BackColor = [System.Drawing.Color]::Transparent
$subtitleLabel.AutoSize = $true
$subtitleLabel.Location = New-Object System.Drawing.Point(28, 78)
$form.Controls.Add($subtitleLabel)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Font = New-Object System.Drawing.Font("Lucida Console", 10, [System.Drawing.FontStyle]::Bold)
$statusLabel.AutoSize = $false
$statusLabel.Size = New-Object System.Drawing.Size(175, 32)
$statusLabel.Location = New-Object System.Drawing.Point(26, 122)
$statusLabel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$form.Controls.Add($statusLabel)

$detailLabel = New-Object System.Windows.Forms.Label
$detailLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$detailLabel.ForeColor = $Y2KColors.Muted
$detailLabel.BackColor = [System.Drawing.Color]::Transparent
$detailLabel.Size = New-Object System.Drawing.Size(255, 42)
$detailLabel.Location = New-Object System.Drawing.Point(218, 119)
$form.Controls.Add($detailLabel)

$logLabel = New-Object System.Windows.Forms.Label
$logLabel.Font = New-Object System.Drawing.Font("Lucida Console", 8)
$logLabel.ForeColor = $Y2KColors.Pink
$logLabel.BackColor = [System.Drawing.Color]::Transparent
$logLabel.Size = New-Object System.Drawing.Size(448, 55)
$logLabel.Location = New-Object System.Drawing.Point(26, 171)
$form.Controls.Add($logLabel)

$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = "START"
$startButton.Size = New-Object System.Drawing.Size(132, 36)
$startButton.Location = New-Object System.Drawing.Point(26, 260)
Set-Y2KButton $startButton $Y2KColors.Lime
$form.Controls.Add($startButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = "STOP"
$stopButton.Size = New-Object System.Drawing.Size(132, 36)
$stopButton.Location = New-Object System.Drawing.Point(184, 260)
Set-Y2KButton $stopButton $Y2KColors.Pink
$form.Controls.Add($stopButton)

$logButton = New-Object System.Windows.Forms.Button
$logButton.Text = "OPEN LOG"
$logButton.Size = New-Object System.Drawing.Size(132, 36)
$logButton.Location = New-Object System.Drawing.Point(342, 260)
Set-Y2KButton $logButton $Y2KColors.Aqua
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
            $statusLabel.Text = "ONLINE // $($status.Text)"
            $statusLabel.ForeColor = $Y2KColors.Lime
            $statusLabel.BackColor = [System.Drawing.Color]::FromArgb(28, 48, 47)
            $notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
        } else {
            $statusLabel.Text = "OFFLINE // $($status.Text)"
            $statusLabel.ForeColor = $Y2KColors.Pink
            $statusLabel.BackColor = [System.Drawing.Color]::FromArgb(55, 24, 64)
            $notifyIcon.Icon = [System.Drawing.SystemIcons]::Warning
        }

        $detailLabel.Text = "$($status.Detail) Process count: $($status.ProcessCount)."
        $logLabel.Text = "LOG FEED // $(Get-LastLogLine)"
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
$notifyIcon.Add_Click({
    param($sender, $eventArgs)
    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        & $showAction
    }
})
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
