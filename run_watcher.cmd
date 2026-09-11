@echo off
setlocal

cd /d "%~dp0"

if not exist logs mkdir logs

set "PYTHON_EXE="
set "PYTHON_SELECTOR="
for /f "delims=" %%P in ('where.exe python.exe 2^>nul') do (
    if not defined PYTHON_EXE set "PYTHON_EXE=%%P"
)
if not defined PYTHON_EXE if exist "%SystemRoot%\py.exe" (
    set "PYTHON_EXE=%SystemRoot%\py.exe"
    set "PYTHON_SELECTOR=-3"
)
if not defined PYTHON_EXE (
    echo [error] Python 3 was not found. Install Python, then restart Ladle Me Jobs.
    exit /b 1
)

:loop
echo [watchdog] starting scraper at %date% %time%
"%PYTHON_EXE%" %PYTHON_SELECTOR% -u scraper.py --loop --interval 10
set EXIT_CODE=%ERRORLEVEL%
echo [watchdog] scraper exited with code %EXIT_CODE% at %date% %time%; restarting in 30 seconds
timeout /t 30 /nobreak >nul
goto loop
