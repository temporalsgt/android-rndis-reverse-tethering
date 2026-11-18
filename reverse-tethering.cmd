@echo off
setlocal EnableExtensions
REM Fallback: reverse tethering via Gnirehtet (VPN). Butuh binary di gnirehtet\.

set "BASE=%~dp0"
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

set "SERIAL=%~1"
if not defined SERIAL set "SERIAL=%ANDROID_SERIAL%"
if not defined SERIAL set "SERIAL=%DEVICE_SERIAL%"
if not defined SERIAL (
  for /f "skip=1 tokens=1,2" %%A in ('"%ADBBIN%" devices 2^>nul') do (
    if not defined SERIAL if "%%B"=="device" set "SERIAL=%%A"
  )
)
if not defined SERIAL (
  echo ERROR: tidak ada perangkat Android terhubung.
  exit /b 1
)

set "GNIREHTET_DIR=%BASE%gnirehtet\gnirehtet-rust-win64"
if not exist "%GNIREHTET_DIR%\gnirehtet.exe" (
  echo ERROR: gnirehtet.exe tidak ditemukan di %GNIREHTET_DIR%
  echo Download Gnirehtet lalu ekstrak ke folder tersebut, atau pakai rndis-tethering.cmd.
  exit /b 1
)

set "PATH=%BASE%tools\platform-tools;%USERPROFILE%\platform-tools;%PATH%"
cd /d "%GNIREHTET_DIR%"
echo Menjalankan reverse tethering untuk %SERIAL% ...
echo Tekan Ctrl+C untuk menghentikan.
echo.
gnirehtet.exe run %SERIAL%
