param(
    [switch]$DesktopShortcut
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Launcher = Join-Path $Root "launch_ladle_me_jobs.vbs"
$IconPath = Join-Path $Root "ui\assets\ladle-me-jobs.ico"
$StartupDir = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $StartupDir "RLC Watch.lnk"

if (-not (Test-Path -LiteralPath $Launcher)) {
    throw "Missing $Launcher"
}

$wscript = Join-Path $env:SystemRoot "System32\wscript.exe"
$shell = New-Object -ComObject WScript.Shell

function Install-LadleShortcut([string]$Path, [string]$Description) {
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $wscript
    $shortcut.Arguments = '"' + $Launcher + '"'
    $shortcut.WorkingDirectory = $Root
    $shortcut.WindowStyle = 7
    $shortcut.Description = $Description
    if (Test-Path -LiteralPath $IconPath) {
        $shortcut.IconLocation = "$IconPath,0"
    }
    $shortcut.Save()

    return [pscustomobject]@{
        Shortcut = $Path
        TargetPath = $shortcut.TargetPath
        Arguments = $shortcut.Arguments
        WorkingDirectory = $shortcut.WorkingDirectory
        IconLocation = $shortcut.IconLocation
    }
}

$installed = @(
    Install-LadleShortcut `
        -Path $ShortcutPath `
        -Description "Launch Ladle Me Jobs at Windows sign-in."
)

if ($DesktopShortcut) {
    $desktopPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "Ladle Me Jobs.lnk"
    $installed += Install-LadleShortcut `
        -Path $desktopPath `
        -Description "Open the Ladle Me Jobs residence-life job watcher."
}

$installed | ConvertTo-Json -Compress
