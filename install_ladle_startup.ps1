Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Launcher = Join-Path $Root "launch_ladle_me_jobs.vbs"
$StartupDir = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $StartupDir "RLC Watch.lnk"

if (-not (Test-Path -LiteralPath $Launcher)) {
    throw "Missing $Launcher"
}

$wscript = Join-Path $env:SystemRoot "System32\wscript.exe"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = $wscript
$shortcut.Arguments = '"' + $Launcher + '"'
$shortcut.WorkingDirectory = $Root
$shortcut.WindowStyle = 7
$shortcut.Description = "Launch Ladle Me Jobs at Windows sign-in."
$shortcut.Save()

[pscustomobject]@{
    Shortcut = $ShortcutPath
    TargetPath = $shortcut.TargetPath
    Arguments = $shortcut.Arguments
    WorkingDirectory = $shortcut.WorkingDirectory
} | ConvertTo-Json -Compress
