@echo off
setlocal

if not exist "%~dp0logs" mkdir "%~dp0logs"

where pythonw.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    start "" pythonw "%~dp0ui\desktop_app.py"
) else (
    start "" "%SystemRoot%\pyw.exe" -3 "%~dp0ui\desktop_app.py"
)
