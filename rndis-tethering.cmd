@echo off
setlocal
set "BASE=%~dp0"
set "ADB=%BASE%tools\platform-tools\adb.exe"
set "PATH=%BASE%tools\platform-tools;%PATH%"

echo ==========================================
echo  Reverse tethering RNDIS - Android device
echo  (terlihat sebagai ETHERNET, bukan VPN)
echo ==========================================
echo.
echo Pastikan: HP ROOT, USB debugging aktif, kabel terhubung.
echo Data seluler TIDAK perlu aktif.
echo.

echo [1/5] Cek ADB...
%ADB% devices | findstr /r /c:"device$" >nul
if errorlevel 1 (
  echo ADB tidak aktif - mencoba re-enumerasi USB...
  powershell -NoProfile -Command "$d = Get-PnpDevice ^| Where-Object { $_.FriendlyName -like '*ADB Interface*' -and $_.Status -eq 'OK' } ^| Select-Object -First 1; if ($d) { Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false; Start-Sleep -Seconds 2; Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false }"
  timeout /t 6 >nul
)

echo [2/5] Pastikan service ICS jalan...
powershell -NoProfile -Command "Start-Service SharedAccess" >nul 2>&1

echo [3/5] Kirim & jalankan setup di HP (root)...
%ADB% push "%BASE%tools\rndis_setup.sh" /data/local/tmp/rndis_setup.sh >nul
%ADB% shell chmod 755 /data/local/tmp/rndis_setup.sh
%ADB% shell "su -c 'sh /data/local/tmp/rndis_setup.sh >/dev/null 2>&1 &'"

echo [4/5] Tunggu gadget + DHCP...
timeout /t 22 >nul

echo [5/5] Aktifkan ICS Windows (Ethernet -^> Ethernet 2)...
cscript //nologo "%BASE%tools\enable_ics.vbs"

echo.
echo === Verifikasi ===
%ADB% shell "ip -o addr show usb0"
%ADB% shell "curl -sS -o /dev/null -w 'HTTP=%%{http_code} time=%%{time_total}s\n' --max-time 15 https://play.google.com"
echo.
echo Log HP: %ADB% shell cat /data/local/tmp/rndis_setup.log
pause
