@echo off
setlocal

cd /d "%~dp0"

if not exist logs mkdir logs

:loop
echo [watchdog] starting scraper at %date% %time%
"C:\Python313\python.exe" -u scraper.py --loop --interval 10
set EXIT_CODE=%ERRORLEVEL%
echo [watchdog] scraper exited with code %EXIT_CODE% at %date% %time%; restarting in 30 seconds
timeout /t 30 /nobreak >nul
goto loop
