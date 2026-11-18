@echo off
setlocal EnableExtensions
set "BASE=%~dp0"

echo ==========================================
echo  Reverse tethering RNDIS - Android universal
echo  (terlihat sebagai ETHERNET, bukan VPN)
echo ==========================================
echo.

rem ---- Pastikan Administrator ----
net session >nul 2>&1
if errorlevel 1 (
  echo ERROR: jalankan sebagai Administrator.
  exit /b 1
)

rem ---- Cari ADB: repo -^> PATH -^> lokasi umum ----
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
  echo ERROR: adb tidak ditemukan. Install platform-tools atau taruh di tools\platform-tools\.
  exit /b 1
)
echo ADB: %ADBBIN%

rem ---- Tentukan serial: argumen -^> env -^> perangkat pertama ----
set "SERIAL=%~1"
if not defined SERIAL set "SERIAL=%ANDROID_SERIAL%"
if not defined SERIAL set "SERIAL=%DEVICE_SERIAL%"
if not defined SERIAL (
  for /f "skip=1 tokens=1,2" %%A in ('"%ADBBIN%" devices 2^>nul') do (
    if not defined SERIAL if "%%B"=="device" set "SERIAL=%%A"
  )
)
if not defined SERIAL (
  echo ERROR: tidak ada perangkat Android terhubung. Hubungkan kabel USB dan aktifkan USB debugging.
  exit /b 1
)
set ADB="%ADBBIN%" -s %SERIAL%
echo Perangkat: %SERIAL%
echo.

rem ---- Cek koneksi: device / unauthorized / offline ----
echo [0/6] Cek perangkat dan root...
set /a WAIT=0
:wait_device
set "STATE="
for /f "skip=1 tokens=1,2" %%A in ('%ADB% devices 2^>nul') do if "%%A"=="%SERIAL%" set "STATE=%%B"
if /i "%STATE%"=="device" goto :device_ready
if /i "%STATE%"=="unauthorized" (
  echo [INFO] Izinkan USB debugging di layar HP ^(centang "Always allow"^), lalu tunggu...
  ping -n 3 127.0.0.1 >nul
  set /a WAIT+=1
  if %WAIT% LSS 30 goto :wait_device
  echo ERROR: otorisasi USB debugging tidak jadi.
  exit /b 1
)
if /i "%STATE%"=="offline" (
  echo [INFO] ADB offline - mencoba start-server + reconnect...
  "%ADBBIN%" kill-server >nul 2>&1
  "%ADBBIN%" start-server >nul 2>&1
  "%ADBBIN%" reconnect offline >nul 2>&1
  ping -n 5 127.0.0.1 >nul
  set /a WAIT+=1
  if %WAIT% LSS 10 goto :wait_device
  echo ERROR: ADB tetap offline setelah re-enumerasi.
  exit /b 1
)
if not defined STATE (
  ping -n 2 127.0.0.1 >nul
  set /a WAIT+=1
  if %WAIT% LSS 30 goto :wait_device
)
echo ERROR: perangkat %SERIAL% tidak dalam keadaan siap ^(status=%STATE%^).
exit /b 1

:device_ready
%ADB% shell "su -c id" 2>nul | findstr /c:"uid=0" >nul
if errorlevel 1 (
  echo ERROR: root ^(su^) tidak tersedia di perangkat.
  exit /b 1
)
echo Root: OK

echo [1/6] Aktifkan service ICS Windows...
powershell -NoProfile -Command "Set-Service SharedAccess -StartupType Manual; Start-Service SharedAccess" >nul 2>&1

rem ---- Taruh script di direktori root-only bila tersedia (hindari /data/local/tmp) ----
set "REMOTE_SH=/data/local/tmp/rndis_setup.sh"
%ADB% shell "su -c '[ -d /data/adb ] && echo yes'" 2>nul | findstr /c:"yes" >nul
if not errorlevel 1 set "REMOTE_SH=/data/adb/rndis_setup.sh"

echo [2/6] Kirim setup script ke HP (%REMOTE_SH%)...
%ADB% push "%BASE%tools\rndis_setup.sh" "%REMOTE_SH%" >nul
if errorlevel 1 ( echo ERROR: gagal push script. & exit /b 1 )
%ADB% shell "su -c 'chmod 755 %REMOTE_SH%'" >nul 2>&1

echo [3/6] Jalankan setup di HP sebagai root...
%ADB% shell "su -c 'sh %REMOTE_SH% >/dev/null 2>&1 &'"

echo [4/6] Tunggu gadget + DHCP...
ping -n 23 127.0.0.1 >nul

echo [5/6] Aktifkan ICS (deteksi adapter otomatis)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%tools\ics.ps1" -Action Enable
if errorlevel 1 (
  echo ERROR: gagal mengaktifkan ICS. Cek adapter RNDIS / jalankan sebagai Administrator.
  exit /b 1
)

echo [6/6] Verifikasi...
set "IF="
for /f "tokens=2 delims==" %%I in ('%ADB% shell "grep -m1 antarmuka= /data/local/tmp/rndis_setup.log 2^>nul"') do set "IF=%%I"
if defined IF echo Antarmuka terdeteksi: %IF%

set /a TRY=0
:verify
if defined IF (
  %ADB% shell "ip -o addr show dev %IF% 2>nul" | findstr /c:"192.168.137." >nul
) else (
  %ADB% shell "ip -o addr show" | findstr /c:"192.168.137." >nul
)
if not errorlevel 1 goto :verify_ok
set /a TRY+=1
if %TRY% GEQ 12 (
  echo WARNING: IP ICS belum muncul. Cek log HP di bawah ini.
  goto :show_log
)
ping -n 5 127.0.0.1 >nul
goto :verify

:verify_ok
%ADB% shell "if command -v curl >/dev/null 2>&1; then curl -sS -o /dev/null -w 'HTTP=%%{http_code} time=%%{time_total}s\n' --max-time 15 https://play.google.com; elif command -v wget >/dev/null 2>&1; then wget -q -O /dev/null -S --timeout=15 https://play.google.com 2>&1 | grep -m1 HTTP; else echo NO_HTTP_CLIENT; fi"

:show_log
echo.
echo === Log dari HP ===
%ADB% shell cat /data/local/tmp/rndis_setup.log
echo.
echo Selesai. Untuk kembali ke kondisi awal: jalankan restore-default.cmd
exit /b 0
