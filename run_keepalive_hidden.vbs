Option Explicit

Dim shell, fso, root, controlScript, powerShellExe, command, exitCode
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
controlScript = fso.BuildPath(root, "rlc_watch_control.ps1")
powerShellExe = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
shell.CurrentDirectory = root
command = Chr(34) & powerShellExe & Chr(34) & " -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & controlScript & Chr(34) & " Start"
' Start hidden from the outset; a directly scheduled console app can flash.
' Wait and propagate failures so Task Scheduler reports the real result.
exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode
