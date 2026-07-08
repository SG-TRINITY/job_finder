@echo off
setlocal

start "Ladle Me Jobs" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0rlc_watch_app.ps1"
