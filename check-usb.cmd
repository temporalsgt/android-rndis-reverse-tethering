@echo off
setlocal
set "BASE=%~dp0"
echo Menjalankan pemeriksaan status USB...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%tools\usb_status.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo [ERROR] usb_status.ps1 gagal, exit code=%RC%
echo Tekan sembarang tombol untuk menutup...
pause >nul
exit /b %RC%
