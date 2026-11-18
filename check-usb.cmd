@echo off
setlocal
set "BASE=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%tools\usb_status.ps1" %*
exit /b %ERRORLEVEL%
