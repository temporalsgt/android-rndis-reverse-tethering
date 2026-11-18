@echo off
REM Reverse tethering PC -> Android device (via Gnirehtet + ADB)
REM Pastikan HP terhubung USB, USB debugging aktif, dan GNIREHTET_SERIAL sesuai serial HP.

set "BASE=%~dp0"
set "ADB_DIR=%BASE%tools\platform-tools"
set "GNIREHTET_DIR=%BASE%gnirehtet\gnirehtet-rust-win64"
set "PATH=%ADB_DIR%;%PATH%"
if "%GNIREHTET_SERIAL%"=="" set "GNIREHTET_SERIAL=REDACTED_SERIAL"

cd /d "%GNIREHTET_DIR%"
echo Menjalankan reverse tethering untuk %GNIREHTET_SERIAL% ...
echo Tekan Ctrl+C untuk menghentikan.
echo.
gnirehtet.exe run %GNIREHTET_SERIAL%
