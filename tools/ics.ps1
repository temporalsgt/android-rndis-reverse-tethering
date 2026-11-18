<#
.SYNOPSIS
    Aktifkan / nonaktifkan Internet Connection Sharing (ICS) tanpa hardcode
    nama adapter. Adapter public dideteksi dari default route; adapter private
    dideteksi dari deskripsi RNDIS / Remote NDIS.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File ics.ps1 -Action Enable
    powershell -NoProfile -ExecutionPolicy Bypass -File ics.ps1 -Action Disable
    powershell -NoProfile -ExecutionPolicy Bypass -File ics.ps1 -Action Enable -PublicName "Ethernet" -PrivateName "Ethernet 2"

.NOTES
    Counter-intuitive tapi sesuai implementasi Windows:
      EnableSharing(0) = public (berinternet)
      EnableSharing(1) = private (dibagikan)
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Enable', 'Disable')]
    [string]$Action,

    [string]$PublicName,
    [string]$PrivateName
)

$ErrorActionPreference = 'Stop'

function Get-PublicAdapterName {
    param([string]$Override)

    if ($Override) {
        $adapter = Get-NetAdapter -Name $Override -ErrorAction SilentlyContinue
        if ($adapter) { return $adapter.Name }
        throw "Adapter public '$Override' tidak ditemukan."
    }

    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric | Select-Object -First 1
    if ($route) {
        $adapter = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue
        if ($adapter) { return $adapter.Name }
    }

    $adapter = Get-NetAdapter |
        Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'RNDIS|Remote NDIS' } |
        Select-Object -First 1
    if ($adapter) { return $adapter.Name }

    return $null
}

function Get-PrivateAdapterName {
    param([string]$Override)

    if ($Override) {
        $adapter = Get-NetAdapter -Name $Override -ErrorAction SilentlyContinue
        if ($adapter) { return $adapter.Name }
        throw "Adapter private '$Override' tidak ditemukan."
    }

    $candidates = @(Get-NetAdapter |
        Where-Object {
            $_.InterfaceDescription -match 'RNDIS|Remote NDIS' -or
            $_.Name -match 'RNDIS'
        })
    if ($candidates.Count -eq 0) { return $null }

    # Prioritaskan adapter yang sudah memiliki IP ICS: ini yang paling mungkin
    # menjadi sisi aktif, bukan adapter stale dari sesi sebelumnya.
    $withIcsIp = @($candidates | Where-Object {
        $ips = @(Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
        @($ips | Where-Object { $_.IPAddress -like '192.168.137.*' }).Count -gt 0
    })
    if ($withIcsIp.Count -gt 0) {
        return @($withIcsIp | Sort-Object InterfaceIndex | Select-Object -First 1)[0].Name
    }

    # Fallback: yang Up, lalu yang paling baru dibuat (InterfaceIndex terbesar).
    return @($candidates |
        Sort-Object -Property @{ Expression = { if ($_.Status -eq 'Up') { 0 } else { 1 } } },
                                @{ Expression = { -$_.InterfaceIndex } } |
        Select-Object -First 1)[0].Name
}

function Get-IcsConnection {
    param($Netshare, [string]$Name, [int]$Attempts = 5)

    for ($i = 1; $i -le $Attempts; $i++) {
        foreach ($conn in $Netshare.EnumEveryConnection) {
            $props = $Netshare.NetConnectionProps($conn)
            if ($props.Name -eq $Name) { return $conn }
        }
        Start-Sleep -Seconds 1
    }
    return $null
}

function Set-SharingState {
    param($Netshare, $Connection, [ValidateSet('Public', 'Private', 'Off')] [string]$Role)

    $cfg = $Netshare.INetSharingConfigurationForINetConnection($Connection)

    if ($Role -eq 'Off') {
        if ($cfg.SharingEnabled) { $cfg.DisableSharing() }
        return
    }

    # Idempoten: jangan EnableSharing ulang jika sudah sesuai (COM bisa error 0x80040201).
    $wantType = if ($Role -eq 'Public') { 0 } else { 1 }
    if ($cfg.SharingEnabled -and $cfg.SharingConnectionType -eq $wantType) { return }
    $cfg.EnableSharing($wantType)
}

$public = Get-PublicAdapterName -Override $PublicName
if (-not $public) {
    Write-Error "Tidak ada adapter dengan default route. Periksa koneksi internet PC."
    exit 1
}

$private = Get-PrivateAdapterName -Override $PrivateName
if ($Action -eq 'Enable' -and -not $private) {
    Write-Error "Adapter RNDIS tidak ditemukan. Jalankan rndis-tethering.cmd dulu / cek kabel USB."
    exit 1
}
if ($private -and $private -eq $public) {
    Write-Error "Adapter public dan private sama ($public). Tentukan dengan -PublicName / -PrivateName."
    exit 1
}

$netshare = $null
$pubConn = $null
$privConn = $null
$lastError = $null
$message = $null

try {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $netshare = New-Object -ComObject HNetCfg.HNetShare.1
        $pubConn = Get-IcsConnection -Netshare $netshare -Name $public
        $privConn = $null
        if ($private) { $privConn = Get-IcsConnection -Netshare $netshare -Name $private }

        if (-not $pubConn -or ($Action -eq 'Enable' -and -not $privConn)) {
            $lastError = "Koneksi ICS belum terdaftar (public=$public, private=$private)."
            Start-Sleep -Seconds 2
            continue
        }

        try {
            if ($Action -eq 'Enable') {
                Set-SharingState -Netshare $netshare -Connection $pubConn  -Role Public
                Set-SharingState -Netshare $netshare -Connection $privConn -Role Private
                $message = "ICS aktif: $public -> $private"
            }
            else {
                Set-SharingState -Netshare $netshare -Connection $pubConn -Role Off
                if ($privConn) { Set-SharingState -Netshare $netshare -Connection $privConn -Role Off }
                $message = "ICS nonaktif ($public$(if ($private) { ", $private" }))."
            }
            break
        }
        catch {
            $lastError = $_.Exception.Message
            # State ICS kadang stale (0x80040201). Restart service lalu coba lagi.
            Start-Sleep -Seconds 2
            Restart-Service SharedAccess -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }
    }
}
finally {
    # Lepaskan objek COM agar tidak menumpuk di proses PowerShell yang dipanggil berulang.
    foreach ($obj in @($privConn, $pubConn, $netshare)) {
        if ($null -ne $obj) {
            try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($obj) } catch { }
        }
    }
}

if ($message) {
    Write-Output $message
    exit 0
}

Write-Error "Gagal mengubah ICS setelah 3 percobaan: $lastError"
exit 1
