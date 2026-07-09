Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

root = fso.GetParentFolderName(WScript.ScriptFullName)
appPath = fso.BuildPath(fso.BuildPath(root, "ui"), "desktop_app.py")

command = "C:\Python313\pythonw.exe " & Chr(34) & appPath & Chr(34)
' pythonw.exe has no console subsystem at all (unlike python.exe run
' hidden), so no window/taskbar flash of any kind before the app's own
' native window (via pywebview) appears. Closing that window minimizes to
' the tray; use Exit from the tray menu to actually quit. The
' scraper/watchdog loop keeps running independently once started from the
' UI - STOP in the UI is what actually stops it.
shell.Run command, 0, False
