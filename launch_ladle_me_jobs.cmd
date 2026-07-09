@echo off
setlocal

if not exist "%~dp0logs" mkdir "%~dp0logs"

start "Ladle Me Jobs" "C:\Python313\pythonw.exe" "%~dp0ui\desktop_app.py"
