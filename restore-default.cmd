@echo off
setlocal EnableExtensions
set "BASE=%~dp0"

echo ==========================================
echo  Kembalikan kondisi awal
echo ==========================================
echo.

rem ---- Cari ADB ----
set "ADBBIN="
if exist "%BASE%tools\platform-tools\adb.exe" set "ADBBIN=%BASE%tools\platform-tools\adb.exe"
if not defined ADBBIN (
  for /f "delims=" %%A in ('where adb 2^>nul') do if not defined ADBBIN set "ADBBIN=%%A"
)
if not defined ADBBIN (
  for %%P in ("%USERPROFILE%\platform-tools\adb.exe" "C:\platform-tools\adb.exe" "%ProgramFiles%\platform-tools\adb.exe") do (
    if not defined ADBBIN if exist %%~P set "ADBBIN=%%~P"
  )
)
if not defined ADBBIN (
  echo ERROR: adb tidak ditemukan.
  exit /b 1
)

rem ---- Tentukan serial ----
set "SERIAL=%~1"
if not defined SERIAL set "SERIAL=%ANDROID_SERIAL%"
if not defined SERIAL set "SERIAL=%DEVICE_SERIAL%"
if not defined SERIAL (
  for /f "skip=1 tokens=1,2" %%A in ('"%ADBBIN%" devices 2^>nul') do (
    if not defined SERIAL if "%%B"=="device" set "SERIAL=%%A"
  )
)
if defined SERIAL (
  set ADB="%ADBBIN%" -s %SERIAL%
) else (
  set ADB="%ADBBIN%"
)

echo [1/3] Matikan ICS Windows...
powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%tools\ics.ps1" -Action Disable

rem ---- Service SharedAccess sengaja DIBIARKAN (Manual). Jangan dimatikan permanen. ----

echo [2/3] Turunkan antarmuka RNDIS di HP...
set "IF="
for /f "tokens=2 delims==" %%I in ('%ADB% shell grep -m1 antarmuka= /data/local/tmp/rndis_setup.log 2^>nul') do set "IF=%%I"
if defined IF (
  echo Menurunkan %IF% ...
  %ADB% shell "su -c 'ip link set %IF% down'" >nul 2>&1
) else (
  echo Log tidak ditemukan - mencoba nama antarmuka umum...
  for %%I in (usb0 usb1 usb2 usb3 usb4 usb5 usb6 usb7 usb8 usb9 eth0 eth1 eth2 eth3 eth4 eth5 rndis0 rndis1) do (
    %ADB% shell "su -c 'ip link set %%I down'" >nul 2>&1
  )
)

echo [3/3] Bersihkan script sementara di HP...
%ADB% shell "su -c 'rm -f /data/local/tmp/rndis_setup.sh /data/adb/rndis_setup.sh /data/local/tmp/rndis_setup.log'" >nul 2>&1

echo.
echo Selesai. Cabut kabel atau reboot HP agar USB kembali ke mode ADB normal.
echo (Data seluler sengaja tidak diubah - sesuaikan manual di Settings jika perlu.)
exit /b 0
