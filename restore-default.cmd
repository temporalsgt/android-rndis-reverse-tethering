@echo off
setlocal
set "BASE=%~dp0"
set "ADB=%BASE%tools\platform-tools\adb.exe"
set "PATH=%BASE%tools\platform-tools;%PATH%"

echo ==========================================
echo  Kembalikan kondisi awal
echo ==========================================
echo.

echo [1/3] Matikan ICS Windows...
cscript //nologo "%BASE%tools\disable_ics.vbs"
powershell -NoProfile -Command "Set-Service SharedAccess -StartupType Disabled; Stop-Service SharedAccess" >nul 2>&1

echo [2/3] Pastikan data seluler HP aktif...
%ADB% shell "settings put global mobile_data 1" >nul 2>&1
%ADB% shell "svc data enable" >nul 2>&1

echo [3/4] Matikan antarmuka usb0 di HP (Ethernet -> seluler)...
%ADB% shell "su -c 'ip link set usb0 down'" >nul 2>&1

echo [4/4] Hentikan relay/proxy jika ada...
powershell -NoProfile -Command "Get-Process gnirehtet -ErrorAction SilentlyContinue | Stop-Process -Force" >nul 2>&1

echo.
echo Selesai.
echo Untuk HP: cabut kabel atau reboot - USB kembali ke mode 'adb'
echo (persist.sys.usb.config = adb).
echo.
pause
