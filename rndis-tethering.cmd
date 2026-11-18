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

rem ---- Cek koneksi & root ----
echo [0/6] Cek perangkat dan root...
set /a WAIT=0
:wait_device
%ADB% devices | findstr /c:"%SERIAL%" | findstr /c:"unauthorized" >nul
if not errorlevel 1 (
  echo.
  echo [INFO] Izinkan USB debugging di layar HP ^(centang "Always allow"^), lalu tunggu...
  ping -n 3 127.0.0.1 >nul
  set /a WAIT+=1
  if %WAIT% LSS 30 goto :wait_device
  echo ERROR: otorisasi USB debugging tidak jadi.
  exit /b 1
)
%ADB% shell "su -c id" 2>nul | findstr /c:"uid=0" >nul
if errorlevel 1 (
  echo ERROR: root ^(su^) tidak tersedia di perangkat.
  exit /b 1
)
echo Root: OK

echo [1/6] Aktifkan service ICS Windows...
powershell -NoProfile -Command "Set-Service SharedAccess -StartupType Manual; Start-Service SharedAccess" >nul 2>&1

echo [2/6] Kirim setup script ke HP...
%ADB% push "%BASE%tools\rndis_setup.sh" /data/local/tmp/rndis_setup.sh >nul
if errorlevel 1 ( echo ERROR: gagal push script. & exit /b 1 )
%ADB% shell chmod 755 /data/local/tmp/rndis_setup.sh

echo [3/6] Jalankan setup di HP sebagai root...
%ADB% shell "su -c 'sh /data/local/tmp/rndis_setup.sh >/dev/null 2>&1 &'"

echo [4/6] Tunggu gadget + DHCP...
ping -n 23 127.0.0.1 >nul

echo [5/6] Aktifkan ICS (deteksi adapter otomatis)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%BASE%tools\ics.ps1" -Action Enable
if errorlevel 1 (
  echo ERROR: gagal mengaktifkan ICS. Cek adapter RNDIS / jalankan sebagai Administrator.
  exit /b 1
)

echo [6/6] Verifikasi...
set /a TRY=0
:verify
%ADB% shell "ip -o addr show" 2>nul | findstr /c:"192.168.137." >nul
if not errorlevel 1 goto :verify_ok
set /a TRY+=1
if %TRY% GEQ 12 (
  echo WARNING: IP ICS belum muncul. Cek log HP di bawah ini.
  goto :show_log
)
ping -n 5 127.0.0.1 >nul
goto :verify

:verify_ok
%ADB% shell "curl -sS -o /dev/null -w 'HTTP=%%{http_code} time=%%{time_total}s\n' --max-time 15 https://play.google.com"

:show_log
echo.
echo === Log dari HP ===
%ADB% shell cat /data/local/tmp/rndis_setup.log
echo.
echo Selesai. Untuk kembali ke kondisi awal: jalankan restore-default.cmd
exit /b 0
