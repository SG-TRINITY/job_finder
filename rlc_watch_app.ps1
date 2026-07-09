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
$BoardsFile = Join-Path $Root "boards.json"
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
    $watchdogRunning = [bool]$watchdog
    $scraperRunning = [bool]$scraper

    if ($watchdogRunning -and $scraperRunning) {
        return @{
            Running = $true
            WatchdogRunning = $true
            ScraperRunning = $true
            Text = "Running"
            Detail = "Watchdog and scraper are active."
            ProcessCount = $processes.Count
        }
    }
    if ($scraperRunning) {
        return @{
            Running = $true
            WatchdogRunning = $false
            ScraperRunning = $true
            Text = "Running without watchdog"
            Detail = "Scraper is active, but the watchdog is not."
            ProcessCount = $processes.Count
        }
    }
    return @{
        Running = $false
        WatchdogRunning = $watchdogRunning
        ScraperRunning = $false
        Text = "Stopped"
        Detail = "No watcher process is running."
        ProcessCount = $processes.Count
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

function Get-LastLogLines([int]$Count = 12) {
    if (-not (Test-Path -LiteralPath $LogFile)) {
        return @()
    }
    $lines = @(Get-Content -LiteralPath $LogFile -Tail $Count -ErrorAction SilentlyContinue)
    return @($lines | Where-Object { $_ -and $_.Trim() -ne '' })
}

function Get-LogLineTag([string]$Line) {
    if ($Line -match '\[scan\]') { return 'scan' }
    if ($Line -match '\[warn\]|\[error\]') { return 'warn' }
    if ($Line -match '\[ok\].*(emailed|texted|sent)') { return 'hit' }
    if ($Line -match '\[ok\]') { return 'ok' }
    if ($Line -match '\[loop\]|\[watchdog\]') { return 'sys' }
    return 'default'
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
    CRT = [System.Drawing.Color]::FromArgb(11, 4, 31)
    TickerBg = [System.Drawing.Color]::FromArgb(8, 5, 24)
    InkDark = [System.Drawing.Color]::FromArgb(25, 15, 62)
    ChromeLight = [System.Drawing.Color]::FromArgb(248, 247, 255)
    ChromeMid = [System.Drawing.Color]::FromArgb(186, 180, 218)
    ChromeDark = [System.Drawing.Color]::FromArgb(86, 66, 156)
    Aqua = [System.Drawing.Color]::FromArgb(45, 226, 201)
    EBlue = [System.Drawing.Color]::FromArgb(61, 123, 255)
    Violet = [System.Drawing.Color]::FromArgb(138, 75, 255)
    Pink = [System.Drawing.Color]::FromArgb(255, 64, 217)
    Amber = [System.Drawing.Color]::FromArgb(255, 210, 63)
    Lavender = [System.Drawing.Color]::FromArgb(185, 142, 255)
    Lime = [System.Drawing.Color]::FromArgb(157, 255, 63)
    Text = [System.Drawing.Color]::FromArgb(252, 250, 255)
    Muted = [System.Drawing.Color]::FromArgb(215, 220, 255)
}

# ------------------------------------------------------------------
# GDI+ helpers
# ------------------------------------------------------------------

function Enable-DoubleBuffered($Control) {
    $flags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
    $prop = $Control.GetType().GetProperty('DoubleBuffered', $flags)
    if ($prop) { $prop.SetValue($Control, $true, $null) }
}

function Mix-Color([System.Drawing.Color]$A, [System.Drawing.Color]$B, [double]$T) {
    $mixedRed = [int]($A.R + ($B.R - $A.R) * $T)
    $mixedGreen = [int]($A.G + ($B.G - $A.G) * $T)
    $mixedBlue = [int]($A.B + ($B.B - $A.B) * $T)
    return [System.Drawing.Color]::FromArgb($mixedRed, $mixedGreen, $mixedBlue)
}

function Gray-Color([System.Drawing.Color]$C) {
    $l = [int](0.3 * $C.R + 0.59 * $C.G + 0.11 * $C.B)
    return [System.Drawing.Color]::FromArgb($l, $l, $l)
}

function New-MultiGradientBrush {
    param($Rect, [System.Drawing.Color[]]$Colors, [float[]]$Positions, [double]$Angle = 90.0)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($Rect, $Colors[0], $Colors[$Colors.Count - 1], $Angle)
    $cb = New-Object System.Drawing.Drawing2D.ColorBlend($Colors.Count)
    $cb.Colors = $Colors
    $cb.Positions = $Positions
    $brush.InterpolationColors = $cb
    return $brush
}

function New-RoundedPath {
    param($Rect, [double]$Radius)
    $d = [double]$Radius
    $x = $Rect.X; $y = $Rect.Y; $w = $Rect.Width; $h = $Rect.Height
    if ($d -gt $h) { $d = $h }
    if ($d -gt $w) { $d = $w }
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc(($x + $w - $d), $y, $d, $d, 270, 90)
    $path.AddArc(($x + $w - $d), ($y + $h - $d), $d, $d, 0, 90)
    $path.AddArc($x, ($y + $h - $d), $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-StarPath([single]$CenterX, [single]$CenterY, [single]$OuterR, [single]$InnerR) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $points = New-Object System.Collections.Generic.List[System.Drawing.PointF]
    for ($i = 0; $i -lt 10; $i++) {
        $angle = (-90 + $i * 36) * [Math]::PI / 180.0
        $r = if ($i % 2 -eq 0) { $OuterR } else { $InnerR }
        $points.Add((New-Object System.Drawing.PointF(($CenterX + $r * [Math]::Cos($angle)), ($CenterY + $r * [Math]::Sin($angle)))))
    }
    $path.AddPolygon($points.ToArray())
    return $path
}

function Add-Stickers($Graphics, [int]$Width, [int]$Height) {
    $starPath = New-StarPath -CenterX 26 -CenterY ($Height - 112) -OuterR 24 -InnerR 10
    $starBrush = New-MultiGradientBrush -Rect (New-Object System.Drawing.RectangleF(0, ($Height - 138), 52, 52)) -Colors ([System.Drawing.Color[]]@(
            $Y2KColors.Aqua, $Y2KColors.EBlue, $Y2KColors.Violet
        )) -Positions ([float[]]@(0.0, 0.5, 1.0)) -Angle 45.0
    $Graphics.FillPath($starBrush, $starPath)
    $starBrush.Dispose()
    $starPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(230, 255, 255, 255), 1.6)
    $Graphics.DrawPath($starPen, $starPath)
    $starPen.Dispose()
    $starPath.Dispose()

    $smileyCx = $Width - 44
    $smileyCy = 6
    $smileyR = 32
    $faceRect = New-Object System.Drawing.RectangleF(($smileyCx - $smileyR), ($smileyCy - $smileyR), ($smileyR * 2), ($smileyR * 2))
    $whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $Graphics.FillEllipse($whiteBrush, $faceRect)
    $whiteBrush.Dispose()
    $yellowRect = New-Object System.Drawing.RectangleF(($smileyCx - $smileyR + 4), ($smileyCy - $smileyR + 4), (($smileyR - 4) * 2), (($smileyR - 4) * 2))
    $yellowBrush = New-Object System.Drawing.SolidBrush($Y2KColors.Amber)
    $Graphics.FillEllipse($yellowBrush, $yellowRect)
    $yellowBrush.Dispose()
    $facePen = New-Object System.Drawing.Pen($Y2KColors.InkDark, 2)
    $Graphics.DrawEllipse($facePen, $yellowRect)
    $eyeBrush = New-Object System.Drawing.SolidBrush($Y2KColors.InkDark)
    $Graphics.FillEllipse($eyeBrush, ($smileyCx - 11), ($smileyCy - 6), 6, 6)
    $Graphics.FillEllipse($eyeBrush, ($smileyCx + 5), ($smileyCy - 6), 6, 6)
    $eyeBrush.Dispose()
    $mouthRect = New-Object System.Drawing.RectangleF(($smileyCx - 13), ($smileyCy - 6), 26, 22)
    $Graphics.DrawArc($facePen, $mouthRect, 20, 140)
    $facePen.Dispose()
}

function Draw-WordmarkBase($Graphics, [single]$X, [single]$Y) {
    $fontFamily = New-Object System.Drawing.FontFamily("Consolas")
    $emSize = 32.0
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $origin = New-Object System.Drawing.PointF($X, $Y)
    $format = [System.Drawing.StringFormat]::GenericTypographic
    $path.AddString("LADLE ME JOBS", $fontFamily, [int][System.Drawing.FontStyle]::Bold, $emSize, $origin, $format)

    $shadowMatrix = New-Object System.Drawing.Drawing2D.Matrix
    $shadowMatrix.Translate(3, 3)
    $shadowPath = $path.Clone()
    $shadowPath.Transform($shadowMatrix)
    $shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 15, 4, 45))
    $Graphics.FillPath($shadowBrush, $shadowPath)
    $shadowBrush.Dispose()
    $shadowPath.Dispose()

    $bounds = $path.GetBounds()
    $gradRect = New-Object System.Drawing.RectangleF(0, 0, ([Math]::Max($bounds.Right + 10, 10)), ([Math]::Max($bounds.Bottom + 10, 10)))
    $wordBrush = New-MultiGradientBrush -Rect $gradRect -Colors ([System.Drawing.Color[]]@(
            [System.Drawing.Color]::White, $Y2KColors.ChromeMid, $Y2KColors.Lavender, $Y2KColors.Pink
        )) -Positions ([float[]]@(0.0, 0.4, 0.55, 1.0)) -Angle 90.0
    $Graphics.FillPath($wordBrush, $path)
    $wordBrush.Dispose()

    $path.Dispose()
    $fontFamily.Dispose()
}

function Draw-WordmarkGlitch($Graphics, [single]$X, [single]$Y) {
    $fontFamily = New-Object System.Drawing.FontFamily("Consolas")
    $emSize = 32.0
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $origin = New-Object System.Drawing.PointF($X, $Y)
    $format = [System.Drawing.StringFormat]::GenericTypographic
    $path.AddString("LADLE ME JOBS", $fontFamily, [int][System.Drawing.FontStyle]::Bold, $emSize, $origin, $format)

    $matA = New-Object System.Drawing.Drawing2D.Matrix
    $matA.Translate(-4, 1)
    $pathA = $path.Clone(); $pathA.Transform($matA)
    $brushA = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(170, $Y2KColors.Aqua))
    $Graphics.FillPath($brushA, $pathA)
    $brushA.Dispose(); $pathA.Dispose()

    $matB = New-Object System.Drawing.Drawing2D.Matrix
    $matB.Translate(4, -1)
    $pathB = $path.Clone(); $pathB.Transform($matB)
    $brushB = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(170, $Y2KColors.Pink))
    $Graphics.FillPath($brushB, $pathB)
    $brushB.Dispose(); $pathB.Dispose()

    $path.Dispose()
    $fontFamily.Dispose()
}

function Build-BackgroundBitmap([int]$Width, [int]$Height) {
    $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $full = New-Object System.Drawing.Rectangle(0, 0, $Width, $Height)

    # outer pearlescent chrome border frame (the "device" bezel)
    $framePath = New-RoundedPath -Rect $full -Radius 26
    $frameBrush = New-MultiGradientBrush -Rect $full -Colors ([System.Drawing.Color[]]@(
            $Y2KColors.ChromeLight, $Y2KColors.ChromeMid, $Y2KColors.ChromeDark, $Y2KColors.ChromeLight
        )) -Positions ([float[]]@(0.0, 0.38, 0.62, 1.0)) -Angle 160.0
    $g.FillPath($frameBrush, $framePath)
    $frameBrush.Dispose()
    $framePath.Dispose()

    # clip everything else to the inset, rounded "device-inner" silhouette
    $deviceRect = New-Object System.Drawing.Rectangle(7, 7, ($Width - 14), ($Height - 14))
    $devicePath = New-RoundedPath -Rect $deviceRect -Radius 20
    $g.SetClip($devicePath)
    $devicePath.Dispose()

    $baseBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($full, [System.Drawing.Color]::FromArgb(34, 17, 69), [System.Drawing.Color]::FromArgb(22, 10, 52), 100.0)
    $g.FillRectangle($baseBrush, $full)
    $baseBrush.Dispose()

    $overlayBrush = New-MultiGradientBrush -Rect $full -Colors ([System.Drawing.Color[]]@(
            [System.Drawing.Color]::FromArgb(16, $Y2KColors.Aqua),
            [System.Drawing.Color]::FromArgb(13, $Y2KColors.EBlue),
            [System.Drawing.Color]::FromArgb(16, $Y2KColors.Violet),
            [System.Drawing.Color]::FromArgb(13, $Y2KColors.Pink)
        )) -Positions ([float[]]@(0.0, 0.35, 0.6, 1.0)) -Angle 115.0
    $g.FillRectangle($overlayBrush, $full)
    $overlayBrush.Dispose()

    $headerRect = New-Object System.Drawing.Rectangle(0, 0, $Width, 30)
    $headerBrush = New-MultiGradientBrush -Rect $headerRect -Colors ([System.Drawing.Color[]]@(
            [System.Drawing.Color]::FromArgb(253, 253, 255),
            [System.Drawing.Color]::FromArgb(208, 202, 234),
            [System.Drawing.Color]::FromArgb(165, 156, 206),
            [System.Drawing.Color]::FromArgb(218, 213, 239)
        )) -Positions ([float[]]@(0.0, 0.45, 0.5, 1.0)) -Angle 90.0
    $g.FillRectangle($headerBrush, $headerRect)
    $headerBrush.Dispose()
    $headerLinePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(90, 20, 10, 50))
    $g.DrawLine($headerLinePen, 0, 29, $Width, 29)
    $headerLinePen.Dispose()

    $idFont = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
    $idBrush = New-Object System.Drawing.SolidBrush($Y2KColors.InkDark)
    $g.DrawString("RLC WATCH // Y2K JOB RADAR", $idFont, $idBrush, 14, 8)
    $idBrush.Dispose(); $idFont.Dispose()

    $dotColors = @($Y2KColors.Lime, $Y2KColors.Amber, $Y2KColors.Pink)
    for ($i = 0; $i -lt 3; $i++) {
        $dx = $Width - 26 - ($i * 20)
        $dotBrush = New-Object System.Drawing.SolidBrush($dotColors[2 - $i])
        $g.FillEllipse($dotBrush, $dx, 9, 12, 12)
        $dotBrush.Dispose()
        $dotPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(90, 20, 10, 50))
        $g.DrawEllipse($dotPen, $dx, 9, 12, 12)
        $dotPen.Dispose()
        $hiBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 255, 255, 255))
        $g.FillEllipse($hiBrush, ($dx + 2), 10, 3, 3)
        $hiBrush.Dispose()
    }

    Draw-WordmarkBase -Graphics $g -X $script:WordmarkX -Y $script:WordmarkY

    $tagFont = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
    $tagBrush1 = New-Object System.Drawing.SolidBrush($Y2KColors.Pink)
    $g.DrawString("$([char]0x25B8)", $tagFont, $tagBrush1, 16, 118)
    $tagBrush2 = New-Object System.Drawing.SolidBrush($Y2KColors.Aqua)
    $g.DrawString("chrome alerts for residence life postings", $tagFont, $tagBrush2, 30, 118)
    $tagBrush1.Dispose(); $tagBrush2.Dispose(); $tagFont.Dispose()

    $consoleOuterRect = New-Object System.Drawing.Rectangle(12, 174, 596, 288)
    $consoleOuterPath = New-RoundedPath -Rect $consoleOuterRect -Radius 20
    $consoleOuterBrush = New-MultiGradientBrush -Rect $consoleOuterRect -Colors ([System.Drawing.Color[]]@(
            $Y2KColors.ChromeMid, $Y2KColors.ChromeDark, $Y2KColors.ChromeLight
        )) -Positions ([float[]]@(0.0, 0.55, 1.0)) -Angle 155.0
    $g.FillPath($consoleOuterBrush, $consoleOuterPath)
    $consoleOuterBrush.Dispose()
    $consoleOuterPath.Dispose()

    $consoleRect = New-Object System.Drawing.Rectangle(16, 178, 588, 280)
    $consolePath = New-RoundedPath -Rect $consoleRect -Radius 16
    $consoleBrush = New-Object System.Drawing.SolidBrush($Y2KColors.CRT)
    $g.FillPath($consoleBrush, $consolePath)
    $consoleBrush.Dispose()
    $consolePath.Dispose()

    $dividerPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(90, $Y2KColors.Pink), 1)
    $dividerPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
    $g.DrawLine($dividerPen, 30, 270, 590, 270)
    $dividerPen.Dispose()

    $capFont = New-Object System.Drawing.Font("Consolas", 8, [System.Drawing.FontStyle]::Bold)
    $capBrush = New-Object System.Drawing.SolidBrush($Y2KColors.Pink)
    $g.DrawString("LOG FEED", $capFont, $capBrush, 30, 276)
    $capBrush.Dispose(); $capFont.Dispose()

    $tickerRect = New-Object System.Drawing.Rectangle(0, 528, $Width, 32)
    $tickerBrush = New-Object System.Drawing.SolidBrush($Y2KColors.TickerBg)
    $g.FillRectangle($tickerBrush, $tickerRect)
    $tickerBrush.Dispose()
    $tickerLinePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(40, 255, 255, 255))
    $g.DrawLine($tickerLinePen, 0, 528, $Width, 528)
    $tickerLinePen.Dispose()

    $g.ResetClip()
    Add-Stickers -Graphics $g -Width $Width -Height $Height

    $g.Dispose()
    return $bmp
}

# ------------------------------------------------------------------
# Shared owner-draw handlers
# ------------------------------------------------------------------

$PillPaintHandler = {
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $rect = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 1), ($sender.Height - 1))
    $accent = $sender.Tag.Accent
    if (-not $sender.Enabled) { $accent = Gray-Color $accent }
    $light = Mix-Color $accent ([System.Drawing.Color]::White) 0.5
    $dark = Mix-Color $accent ([System.Drawing.Color]::Black) 0.55

    $path = New-RoundedPath -Rect $rect -Radius $rect.Height
    $gradRect = New-Object System.Drawing.RectangleF($rect.X, $rect.Y, [Math]::Max($rect.Width, 1), [Math]::Max($rect.Height, 1))
    $brush = New-MultiGradientBrush -Rect $gradRect -Colors ([System.Drawing.Color[]]@($light, $accent, $dark)) -Positions ([float[]]@(0.0, 0.45, 1.0)) -Angle 90.0
    $g.FillPath($brush, $path)
    $brush.Dispose()

    if ($sender.Tag.Hover -and $sender.Enabled) {
        $glowPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, 255, 255, 255), 1.6)
        $g.DrawPath($glowPen, $path)
        $glowPen.Dispose()
    }

    $shineRect = New-Object System.Drawing.RectangleF(($rect.Width * 0.08), ($rect.Height * 0.1), ($rect.Width * 0.84), ($rect.Height * 0.38))
    $shinePath = New-RoundedPath -Rect $shineRect -Radius $shineRect.Height
    $shineBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($shineRect, [System.Drawing.Color]::FromArgb(150, 255, 255, 255), [System.Drawing.Color]::FromArgb(0, 255, 255, 255), 90.0)
    $g.FillPath($shineBrush, $shinePath)
    $shineBrush.Dispose(); $shinePath.Dispose()
    $path.Dispose()

    $font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $textRect = New-Object System.Drawing.RectangleF(0, 0, $sender.Width, $sender.Height)

    $shadowRect = New-Object System.Drawing.RectangleF(1, 2, $sender.Width, $sender.Height)
    $shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140, 10, 4, 30))
    $g.DrawString($sender.Text, $font, $shadowBrush, $shadowRect, $sf)
    $shadowBrush.Dispose()

    $textColor = if ($sender.Enabled) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::FromArgb(210, 210, 210) }
    $textBrush = New-Object System.Drawing.SolidBrush($textColor)
    $g.DrawString($sender.Text, $font, $textBrush, $textRect, $sf)
    $textBrush.Dispose()
    $font.Dispose()
}

$LampPaintHandler = {
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $rect = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 1), ($sender.Height - 1))
    $accent = if ($script:LampRunning) { $Y2KColors.Lime } else { $Y2KColors.Pink }

    $bgPath = New-RoundedPath -Rect $rect -Radius $rect.Height
    $bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(30, $accent))
    $g.FillPath($bgBrush, $bgPath)
    $bgBrush.Dispose()
    $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, $accent), 1)
    $g.DrawPath($borderPen, $bgPath)
    $borderPen.Dispose()
    $bgPath.Dispose()

    $pulse = 0.55 + 0.45 * [Math]::Sin($script:LedPhase)
    $alpha = [int](130 + 110 * $pulse)
    $cx = 30; $cy = [int]($rect.Height / 2); $r = 9
    $glowAlpha = [Math]::Max(0, [Math]::Min(90, [int]($alpha / 2)))
    $glowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($glowAlpha, $accent))
    $g.FillEllipse($glowBrush, ($cx - $r - 7), ($cy - $r - 7), (($r + 7) * 2), (($r + 7) * 2))
    $glowBrush.Dispose()
    $ledBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($alpha, $accent))
    $g.FillEllipse($ledBrush, ($cx - $r), ($cy - $r), ($r * 2), ($r * 2))
    $ledBrush.Dispose()
    $hiBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 255, 255, 255))
    $g.FillEllipse($hiBrush, ($cx - 3), ($cy - 4), 4, 4)
    $hiBrush.Dispose()

    $font = New-Object System.Drawing.Font("Consolas", 15, [System.Drawing.FontStyle]::Bold)
    $textBrush = New-Object System.Drawing.SolidBrush($accent)
    $sf = New-Object System.Drawing.StringFormat
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $textRect = New-Object System.Drawing.RectangleF(52, 0, ($rect.Width - 60), $rect.Height)
    $g.DrawString($script:LampText, $font, $textBrush, $textRect, $sf)
    $textBrush.Dispose()
    $font.Dispose()
}

$ChipPaintHandler = {
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $rect = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 1), ($sender.Height - 1))
    $border = $sender.Tag.Border
    $path = New-RoundedPath -Rect $rect -Radius 8
    $bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(24, $border))
    $g.FillPath($bgBrush, $path)
    $bgBrush.Dispose()
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(140, $border))
    $g.DrawPath($pen, $path)
    $pen.Dispose()
    $path.Dispose()

    $font = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Bold)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $textBrush = New-Object System.Drawing.SolidBrush($sender.Tag.TextColor)
    $textRect = New-Object System.Drawing.RectangleF(0, 0, $sender.Width, $sender.Height)
    $g.DrawString($sender.Tag.Text, $font, $textBrush, $textRect, $sf)
    $textBrush.Dispose()
    $font.Dispose()
}

$TickerPaintHandler = {
    param($sender, $e)
    $g = $e.Graphics
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $brush = New-Object System.Drawing.SolidBrush($Y2KColors.Lavender)
    $g.DrawString($script:TickerText, $script:TickerFont, $brush, [single]$script:TickerX, 6.0)
    $brush.Dispose()
}

function New-PillButton {
    param($Parent, [string]$Text, [System.Drawing.Color]$Accent, [int]$X, [int]$Y, [int]$W, [int]$H)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.Size = New-Object System.Drawing.Size($W, $H)
    $lbl.Location = New-Object System.Drawing.Point($X, $Y)
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $lbl.Cursor = [System.Windows.Forms.Cursors]::Hand
    $lbl.Tag = [PSCustomObject]@{ Accent = $Accent; Hover = $false }
    Enable-DoubleBuffered $lbl
    $lbl.Add_Paint($PillPaintHandler)
    $lbl.Add_MouseEnter({ param($s, $e) $s.Tag.Hover = $true; $s.Invalidate() })
    $lbl.Add_MouseLeave({ param($s, $e) $s.Tag.Hover = $false; $s.Invalidate() })
    $Parent.Controls.Add($lbl)
    return $lbl
}

# ------------------------------------------------------------------
# Board count (real data, read once at launch)
# ------------------------------------------------------------------

$script:BoardCount = 0
try {
    if (Test-Path -LiteralPath $BoardsFile) {
        $boardsData = Get-Content -LiteralPath $BoardsFile -Raw | ConvertFrom-Json
        $script:BoardCount = @($boardsData | Where-Object { $_.enabled -ne $false }).Count
    }
} catch {
    Write-AppLog "Board count read error: $($_.Exception.Message)"
}

# ------------------------------------------------------------------
# Form + cached background
# ------------------------------------------------------------------

$script:WordmarkX = 20
$script:WordmarkY = 42
$script:LampRunning = $true
$script:LampText = "ONLINE // Running"
$script:LedPhase = 0.0
$script:GlitchActive = $false
$script:TickerX = 0
$script:TickerTextWidth = 200
$script:TickerFont = New-Object System.Drawing.Font("Consolas", 11)
$script:TickerText = "++ RLC WATCH // LADLE ME JOBS ++ booting radar ++"

$form = New-Object System.Windows.Forms.Form
$form.Text = "Ladle Me Jobs"
$form.ClientSize = New-Object System.Drawing.Size(620, 560)
$form.StartPosition = "CenterScreen"
$form.MaximizeBox = $false
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.BackColor = $Y2KColors.DeepInk
$form.ForeColor = $Y2KColors.Text
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
Enable-DoubleBuffered $form

$script:BgBitmap = Build-BackgroundBitmap -Width $form.ClientSize.Width -Height $form.ClientSize.Height

$form.Add_Paint({
    param($sender, $eventArgs)
    $g = $eventArgs.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    if ($script:BgBitmap) { $g.DrawImageUnscaled($script:BgBitmap, 0, 0) }
    if ($script:GlitchActive) {
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        Draw-WordmarkGlitch -Graphics $g -X $script:WordmarkX -Y $script:WordmarkY
    }
})

# ------------------------------------------------------------------
# Dynamic controls
# ------------------------------------------------------------------

$lampPanel = New-Object System.Windows.Forms.Panel
$lampPanel.Location = New-Object System.Drawing.Point(34, 196)
$lampPanel.Size = New-Object System.Drawing.Size(300, 60)
$lampPanel.BackColor = $Y2KColors.CRT
Enable-DoubleBuffered $lampPanel
$lampPanel.Add_Paint($LampPaintHandler)
$form.Controls.Add($lampPanel)

$detailLabel = New-Object System.Windows.Forms.Label
$detailLabel.Location = New-Object System.Drawing.Point(348, 200)
$detailLabel.Size = New-Object System.Drawing.Size(242, 52)
$detailLabel.BackColor = [System.Drawing.Color]::Transparent
$detailLabel.ForeColor = $Y2KColors.Muted
$detailLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($detailLabel)

$procChipPanel = New-Object System.Windows.Forms.Panel
$procChipPanel.Location = New-Object System.Drawing.Point(470, 230)
$procChipPanel.Size = New-Object System.Drawing.Size(52, 26)
$procChipPanel.BackColor = $Y2KColors.CRT
$procChipPanel.Tag = [PSCustomObject]@{ Text = "0"; Border = $Y2KColors.Aqua; TextColor = $Y2KColors.Aqua }
Enable-DoubleBuffered $procChipPanel
$procChipPanel.Add_Paint($ChipPaintHandler)
$form.Controls.Add($procChipPanel)

$logFeedBox = New-Object System.Windows.Forms.RichTextBox
$logFeedBox.Location = New-Object System.Drawing.Point(30, 296)
$logFeedBox.Size = New-Object System.Drawing.Size(560, 150)
$logFeedBox.ReadOnly = $true
$logFeedBox.TabStop = $false
$logFeedBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$logFeedBox.BackColor = $Y2KColors.CRT
$logFeedBox.ForeColor = $Y2KColors.Text
$logFeedBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$logFeedBox.WordWrap = $false
$logFeedBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$logFeedBox.Cursor = [System.Windows.Forms.Cursors]::Default
$form.Controls.Add($logFeedBox)

$startButton = New-PillButton -Parent $form -Text "START" -Accent $Y2KColors.Lime -X 16 -Y 472 -W 188 -H 44
$stopButton = New-PillButton -Parent $form -Text "STOP" -Accent $Y2KColors.Pink -X 216 -Y 472 -W 188 -H 44
$logButton = New-PillButton -Parent $form -Text "OPEN LOG" -Accent $Y2KColors.Aqua -X 416 -Y 472 -W 188 -H 44

$tickerPanel = New-Object System.Windows.Forms.Panel
$tickerPanel.Location = New-Object System.Drawing.Point(0, 528)
$tickerPanel.Size = New-Object System.Drawing.Size(620, 32)
$tickerPanel.BackColor = $Y2KColors.TickerBg
Enable-DoubleBuffered $tickerPanel
$tickerPanel.Add_Paint($TickerPaintHandler)
$form.Controls.Add($tickerPanel)

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

# ------------------------------------------------------------------
# Behaviour
# ------------------------------------------------------------------

function Update-LogFeed {
    $lines = Get-LastLogLines -Count 12
    $logFeedBox.Clear()
    if ($lines.Count -eq 0) {
        $logFeedBox.SelectionColor = $Y2KColors.Muted
        $logFeedBox.AppendText("log file has not been created yet.")
    } else {
        foreach ($line in $lines) {
            $tag = Get-LogLineTag $line
            $color = switch ($tag) {
                'scan' { $Y2KColors.Aqua }
                'hit' { $Y2KColors.Lime }
                'warn' { $Y2KColors.Pink }
                'sys' { $Y2KColors.Lavender }
                'ok' { $Y2KColors.ChromeMid }
                default { $Y2KColors.Muted }
            }
            $logFeedBox.SelectionColor = $color
            $logFeedBox.AppendText("$line`n")
        }
    }
    $logFeedBox.SelectionStart = $logFeedBox.TextLength
    $logFeedBox.ScrollToCaret()
}

function Measure-TickerWidth {
    $g = $tickerPanel.CreateGraphics()
    try {
        $size = $g.MeasureString($script:TickerText, $script:TickerFont)
        $script:TickerTextWidth = [int]$size.Width
    } finally {
        $g.Dispose()
    }
    if ($script:TickerX -lt (-$script:TickerTextWidth)) { $script:TickerX = $tickerPanel.Width }
}

function Refresh-Ui {
    try {
        $status = Get-RlcStatus

        $script:LampRunning = $status.ScraperRunning
        $script:LampText = if ($status.ScraperRunning) { "ONLINE // Running" } else { "OFFLINE // Stopped" }
        $lampPanel.Invalidate()

        $procChipPanel.Tag.Text = "$($status.ProcessCount)"
        $procChipPanel.Tag.Border = if ($status.ScraperRunning) { $Y2KColors.Aqua } else { $Y2KColors.Pink }
        $procChipPanel.Tag.TextColor = $procChipPanel.Tag.Border
        $procChipPanel.Invalidate()

        if ($status.ScraperRunning -and $status.WatchdogRunning) {
            $detailLabel.Text = "Watchdog and scraper are active.`nProcess count:"
        } elseif ($status.ScraperRunning) {
            $detailLabel.Text = "Scraper is checking jobs, but watchdog is not guarding restarts.`nProcess count:"
        } elseif ($status.WatchdogRunning) {
            $detailLabel.Text = "Watchdog is present, but no scraper loop was detected.`nProcess count:"
        } else {
            $detailLabel.Text = "No scraper or watchdog process is running.`nPress START to resume alerts."
        }
        $detailLabel.ForeColor = if ($status.ScraperRunning) { $Y2KColors.Muted } else { $Y2KColors.Pink }
        $procChipPanel.Visible = $status.Running

        Update-LogFeed

        $lastWrite = if (Test-Path -LiteralPath $LogFile) {
            (Get-Item -LiteralPath $LogFile).LastWriteTime.ToString("yyyy-MM-dd HH:mm")
        } else {
            "never"
        }
        $script:TickerText = "++ RLC WATCH // LADLE ME JOBS ++ monitoring $($script:BoardCount) boards ++ status: $($status.Text) ++ last log activity: $lastWrite ++ processes: $($status.ProcessCount) ++ "
        Measure-TickerWidth

        $trayText = "Ladle Me Jobs - $($status.Text)"
        if ($trayText.Length -gt 63) { $trayText = $trayText.Substring(0, 63) }
        $notifyIcon.Text = $trayText
        $notifyIcon.Icon = if ($status.ScraperRunning) { [System.Drawing.SystemIcons]::Information } else { [System.Drawing.SystemIcons]::Warning }

        $startButton.Enabled = -not $status.Running
        $stopButton.Enabled = $status.Running
        $startMenuItem.Enabled = -not $status.Running
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

# ------------------------------------------------------------------
# Timers: status poll (5s), LED pulse (120ms), ticker scroll (40ms),
# and an occasional brief wordmark glitch (~7s, ~320ms duration).
# ------------------------------------------------------------------

$refreshTimer = New-Object System.Windows.Forms.Timer
$refreshTimer.Interval = 5000
$refreshTimer.Add_Tick({ Refresh-Ui })
$refreshTimer.Start()

$ledTimer = New-Object System.Windows.Forms.Timer
$ledTimer.Interval = 120
$ledTimer.Add_Tick({
    $script:LedPhase += 0.35
    if ($script:LedPhase -gt 6.283185) { $script:LedPhase -= 6.283185 }
    $lampPanel.Invalidate()
})
$ledTimer.Start()

$tickerTimer = New-Object System.Windows.Forms.Timer
$tickerTimer.Interval = 40
$tickerTimer.Add_Tick({
    $script:TickerX -= 3
    if ($script:TickerX -lt (-$script:TickerTextWidth)) { $script:TickerX = $tickerPanel.Width }
    $tickerPanel.Invalidate()
})
$tickerTimer.Start()

$glitchOffTimer = New-Object System.Windows.Forms.Timer
$glitchOffTimer.Interval = 320
$glitchOffTimer.Add_Tick({
    $script:GlitchActive = $false
    $form.Invalidate()
    $glitchOffTimer.Stop()
})

$glitchTimer = New-Object System.Windows.Forms.Timer
$glitchTimer.Interval = 7000
$glitchTimer.Add_Tick({
    $script:GlitchActive = $true
    $form.Invalidate()
    $glitchOffTimer.Stop()
    $glitchOffTimer.Start()
})
$glitchTimer.Start()

Refresh-Ui
try {
    [System.Windows.Forms.Application]::Run($form)
} finally {
    Write-AppLog "Controller stopped"
}
