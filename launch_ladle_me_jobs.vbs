Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

Function FindOnPath(fileName)
    pathEntries = Split(shell.ExpandEnvironmentStrings("%PATH%"), ";")
    For Each entry In pathEntries
        If Len(entry) > 0 Then
            candidate = fso.BuildPath(entry, fileName)
            If fso.FileExists(candidate) Then
                FindOnPath = candidate
                Exit Function
            End If
        End If
    Next
    FindOnPath = ""
End Function

root = fso.GetParentFolderName(WScript.ScriptFullName)
appPath = fso.BuildPath(fso.BuildPath(root, "ui"), "desktop_app.py")
pythonLauncher = FindOnPath("pythonw.exe")

If Len(pythonLauncher) > 0 Then
    command = Chr(34) & pythonLauncher & Chr(34) & " " & Chr(34) & appPath & Chr(34)
Else
    pythonLauncher = shell.ExpandEnvironmentStrings("%SystemRoot%\pyw.exe")
    command = Chr(34) & pythonLauncher & Chr(34) & " -3 " & Chr(34) & appPath & Chr(34)
End If
' pythonw.exe has no console subsystem at all (unlike python.exe run
' hidden), so no window/taskbar flash of any kind before the app's own
' native window (via pywebview) appears. Closing that window minimizes to
' the tray; use Exit from the tray menu to actually quit. The
' desktop app starts the scraper/watchdog loop automatically if needed.
' STOP in the UI is what actually stops it.
shell.Run command, 0, False
