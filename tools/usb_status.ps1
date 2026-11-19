<#
.SYNOPSIS
    Cek kondisi USB saat ini: Windows + Android sekaligus.

.DESCRIPTION
    Menampilkan:
      - status perangkat ADB (device/unauthorized/offline)
      - konfigurasi USB di Android (persist/sys.usb.config, fungsi, configfs)
      - device USB yang ter-enumerasi di Windows (VID/PID)
      - adapter Remote NDIS + IP 192.168.137.x
      - service ICS / koneksi sharing
      - kesimpulan: MODE NORMAL atau MODE RNDIS

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\usb_status.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\usb_status.ps1 <SERIAL>
#>
param([string]$Serial)

$ErrorActionPreference = 'Continue'
$BASE = Split-Path -Parent $MyInvocation.MyCommand.Path
$REPO = Split-Path -Parent $BASE

function Write-Head($text) {
    Write-Host ""
    Write-Host "=== $text ===" -ForegroundColor Cyan
}

# ---------------------------------------------------------------- ADB
$adb = $null
$candidates = @(
    (Join-Path $REPO 'tools\platform-tools\adb.exe'),
    (Join-Path $env:USERPROFILE 'platform-tools\adb.exe'),
    'C:\platform-tools\adb.exe',
    (Join-Path $env:ProgramFiles 'platform-tools\adb.exe')
)
foreach ($c in $candidates) { if (-not $adb -and (Test-Path $c)) { $adb = $c } }
if (-not $adb) {
    $cmd = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($cmd) { $adb = $cmd.Source }
}
if (-not $adb) {
    Write-Host "ADB tidak ditemukan." -ForegroundColor Red
    exit 1
}

$devices = @(& $adb devices 2>$null)
$states = @()
foreach ($line in $devices) {
    if ($line -match '^(\S+)\s+(device|unauthorized|offline|recovery|no permissions)\b') {
        $states += [pscustomobject]@{ Serial = $Matches[1]; State = $Matches[2] }
    }
}

if (-not $Serial) {
    $pick = $states | Where-Object { $_.State -eq 'device' } | Select-Object -First 1
    if (-not $pick) { $pick = $states | Select-Object -First 1 }
    if ($pick) { $Serial = $pick.Serial }
}

Write-Head "ADB"
Write-Host "Binary : $adb"
if ($states.Count -eq 0) {
    Write-Host "Perangkat: TIDAK ADA" -ForegroundColor Red
}
else {
    foreach ($s in $states) {
        $color = if ($s.State -eq 'device') { 'Green' } else { 'Yellow' }
        $mark = if ($s.Serial -eq $Serial) { ' <- dipilih' } else { '' }
        Write-Host ("Perangkat: {0} [{1}]{2}" -f $s.Serial, $s.State, $mark) -ForegroundColor $color
    }
}

if (-not $Serial) {
    Write-Host "Tidak ada perangkat untuk diperiksa. Hubungkan kabel & izinkan USB debugging." -ForegroundColor Red
    exit 1
}

function AdbSh([string]$cmd) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $out = & $adb -s $Serial shell $cmd 2>&1
        $txt = ($out | Out-String).Trim()
        # Beberapa perintah Android (mis. svc usb) menulis ke stderr; buang prefix-nya.
        return ($txt -replace '(?m)^adb\.exe\s*:\s*', '')
    }
    finally {
        $ErrorActionPreference = $old
    }
}

# ---------------------------------------------------------------- ANDROID
Write-Head "ANDROID (HP)"
$persist = AdbSh 'getprop persist.sys.usb.config'
$current = AdbSh 'getprop sys.usb.config'
$state = AdbSh 'getprop sys.usb.state'
$functions = AdbSh 'svc usb getFunctions'
Write-Host "persist.sys.usb.config : $persist"
Write-Host "sys.usb.config         : $current"
Write-Host "sys.usb.state          : $state"
Write-Host "fungsi aktif           : $functions"

$links = AdbSh 'ip -o link show'
$usbLinks = @($links -split "`n" | Where-Object { $_ -match '\b(usb|eth|rndis)\d+:' })
if ($usbLinks.Count -eq 0) {
    Write-Host "antarmuka usb/eth/rndis: TIDAK ADA" -ForegroundColor Yellow
}
else {
    foreach ($l in $usbLinks) { Write-Host "antarmuka: $($l.Trim())" }
}

$addrs = AdbSh 'ip -o addr show'
$icsAddr = @($addrs -split "`n" | Where-Object { $_ -match '192\.168\.137\.' })
if ($icsAddr.Count -eq 0) {
    Write-Host "IP ICS 192.168.137.x   : TIDAK ADA" -ForegroundColor Yellow
}
else {
    foreach ($a in $icsAddr) { Write-Host "IP ICS: $($a.Trim())" -ForegroundColor Green }
}

$eth = AdbSh 'dumpsys ethernet'
$tracked = @($eth -split "`n" | Where-Object { $_ -match '\b(usb|eth)\d+:' })
$filter = @($eth -split "`n" | Where-Object { $_ -match 'interface name filter' }) | Select-Object -First 1
Write-Host "EthernetTracker filter : $($filter.Trim())"
if ($tracked.Count -eq 0) {
    Write-Host "Ethernet terlacak      : TIDAK ADA" -ForegroundColor Yellow
}
else {
    foreach ($t in $tracked) { Write-Host "Ethernet terlacak: $($t.Trim())" -ForegroundColor Green }
}

$cfgCmd = @'
for g in /config/usb_gadget/*; do
  [ -d "$g/configs" ] || continue
  echo "gadget=$g"
  echo "UDC=$(cat $g/UDC 2>/dev/null)"
  for c in $g/configs/*; do
    [ -d "$c" ] || continue
    echo "config=$c"
    echo "configuration=$(cat $c/strings/0x409/configuration 2>/dev/null)"
  done
  echo "idVendor=$(cat $g/idVendor 2>/dev/null)"
  echo "idProduct=$(cat $g/idProduct 2>/dev/null)"
done
'@
$cfg = AdbSh "su -c '$cfgCmd'"
if ($cfg) { Write-Host "configfs (UDC/config/VID/PID):" ; Write-Host $cfg }

$log = AdbSh 'cat /data/local/tmp/rndis_setup.log'
if ($log -match '=== mulai') {
    Write-Host "log rndis_setup (sesi terakhir): ADA"
    foreach ($line in ($log -split "`n")) {
        if ($line -match '^(antarmuka|addr|dns|ethernet)=') { Write-Host "  $($line.Trim())" }
    }
}
else {
    Write-Host "log rndis_setup        : TIDAK ADA" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- WINDOWS
Write-Head "WINDOWS"

$pnp = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object {
        $_.InstanceId -like 'USB\*' -and
        ($_.InstanceId -match [regex]::Escape($Serial) -or
         $_.FriendlyName -match 'Android|ADB|NDIS|MTP|MIDI|PTP|Portable')
    })
if ($pnp.Count -eq 0) {
    Write-Host "Device USB HP          : TIDAK ter-enumerasi" -ForegroundColor Red
}
else {
    foreach ($d in $pnp) {
        $vidpid = if ($d.InstanceId -match 'VID_([0-9A-F]+)&PID_([0-9A-F]+)') { "$($Matches[1]):$($Matches[2])" } else { '-' }
        Write-Host ("Device: {0} [{1}] VID:PID={2}" -f $d.FriendlyName, $d.Status, $vidpid)
        Write-Host "        $($d.InstanceId)"
    }
}

$rndis = @(Get-NetAdapter -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceDescription -match 'RNDIS|Remote NDIS' })
if ($rndis.Count -eq 0) {
    Write-Host "Adapter Remote NDIS    : TIDAK ADA" -ForegroundColor Yellow
}
else {
    foreach ($a in $rndis) {
        $ip = (Get-NetIPAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
        Write-Host ("Adapter: {0} [{1}] IP={2}" -f $a.Name, $a.Status, $ip) -ForegroundColor Green
    }
}

$svc = Get-Service SharedAccess -ErrorAction SilentlyContinue
Write-Host "SharedAccess           : $($svc.Status) / $($svc.StartType)"
try {
    $ns = New-Object -ComObject HNetCfg.HNetShare.1
    $shared = @()
    foreach ($c in $ns.EnumEveryConnection) {
        $p = $ns.NetConnectionProps($c)
        $cfg2 = $ns.INetSharingConfigurationForINetConnection($c)
        if ($cfg2.SharingEnabled) {
            $role = if ($cfg2.SharingConnectionType -eq 0) { 'public' } else { 'private' }
            $shared += "$($p.Name) ($role)"
        }
    }
    Write-Host "ICS sharing            : $(if ($shared.Count) { $shared -join ', ' } else { 'TIDAK ADA' })"
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
}
catch {
    Write-Host "ICS sharing            : tidak bisa dibaca ($($_.Exception.Message))"
}

# ---------------------------------------------------------------- KESIMPULAN
Write-Head "KESIMPULAN"
# VID/PID tidak dipakai sebagai penentu RNDIS: banyak perangkat memakai
# 05C6:9024 untuk ADB normal. Yang dipakai adalah string konfigurasi configfs.
$hasRndisCfg = $cfg -match 'rndis'
$hasRndisAdapter = $rndis.Count -gt 0
$hasUsbIf = $usbLinks.Count -gt 0
$hasIcsIp = $icsAddr.Count -gt 0

if ($hasRndisAdapter -and $hasUsbIf -and $hasIcsIp) {
    Write-Host "MODE RNDIS / reverse tethering SEDANG AKTIF." -ForegroundColor Green
    Write-Host "Gunakan restore-default.cmd lalu cabut/reboot HP untuk kembali normal."
}
elseif ($current -match 'rndis' -or $hasRndisCfg -or $hasRndisAdapter) {
    Write-Host "KONDISI TRANSISI: ada jejak RNDIS tapi belum aktif penuh." -ForegroundColor Yellow
    Write-Host "Cek log HP / ICS, atau jalankan ulang rndis-tethering.cmd."
}
else {
    Write-Host "MODE NORMAL (ADB/MTP) - belum masuk RNDIS." -ForegroundColor Cyan
    if ($persist -ne 'adb' -and $persist -ne '') {
        Write-Host "Catatan: persist.sys.usb.config = '$persist' (bawaan: 'adb')." -ForegroundColor Yellow
    }
}
