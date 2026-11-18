# Reverse Tethering — PC → Android device

Berbagi koneksi internet **PC Windows** ke **Android device** lewat kabel USB, tanpa VPN dan tanpa root tambahan (cukup pakai root yang sudah ada).

Proyek ini didokumentasikan dari hasil eksperimen langsung di perangkat:

| Item | Nilai |
|---|---|
| Perangkat | `Android device` (`device`) |
| Android | 17 (API 37) |
| Root | APatch (`/data/adb/ap`) |
| PC | Windows 10 Pro 19045 |
| ADB | `tools/platform-tools/adb.exe` |
| Serial | `REDACTED_SERIAL` (ubah di script kalau berbeda) |

---

## Dua metode

| Aspek | Gnirehtet (VPN) | **RNDIS → Ethernet** ✅ |
|---|---|---|
| Cara kerja | App VPN userspace, relay via ADB | Antarmuka USB kernel, DHCP + NAT |
| Transport di Play Store | `TRANSPORT_VPN` | `TRANSPORT_ETHERNET` |
| **Google Play Store** | ❌ sering gagal / deteksi VPN | ✅ normal |
| ICMP / ping | ❌ dibuang | ✅ jalan |
| IPv6 | ❌ `::/0 unreachable` | ✅ sesuai jaringan |
| App deteksi VPN | ❌ ya | ✅ tidak |
| Butuh data seluler | ya (underlying network) | **tidak** |
| Butuh root | tidak | ya |
| Stabilitas | tinggi | sedang (gadget HAL bisa reset) |

> **Rekomendasi:** pakai metode RNDIS → Ethernet (`rndis-tethering.cmd`). Simpan Gnirehtet hanya sebagai cadangan.

---

## Hasil terverifikasi (metode RNDIS)

- ✅ `play.google.com` → HTTP 302
- ✅ Play Store membuka konten live (rekomendasi, event, pencarian)
- ✅ DNS resolve lewat `192.168.137.1`
- ✅ `ping google.com` → balas (ICMP jalan)
- ✅ Semua route lewat `usb0` (Ethernet), bukan VPN
- ✅ Tetap jalan walau **data seluler dimatikan**
- ✅ PC tetap memakai internetnya sendiri (`192.168.1.104`, DHCP)

---

## Persyaratan

1. HP sudah **root** (APatch / Magisk) dan **USB debugging** aktif.
2. Kabel USB terhubung ke PC.
3. Windows dengan hak **Administrator**.
4. ADB sudah ada di `tools/platform-tools/`.
5. Service Windows `SharedAccess` (ICS) akan diaktifkan otomatis oleh script.

---

## Pemakaian (metode RNDIS)

### 1. Hubungkan HP

```powershell
.\tools\platform-tools\adb.exe devices -l
```

Harus muncul:

```
REDACTED_SERIAL    device product:device model:Android device device:device
```

Kalau statusnya `offline` / tidak muncul, lihat [Troubleshooting](#troubleshooting).

### 2. Jalankan

```cmd
rndis-tethering.cmd
```

Script akan:
1. Cek ADB (auto re-enumerasi USB kalau perlu)
2. Aktifkan service ICS Windows
3. Kirim & jalankan `tools/rndis_setup.sh` di HP sebagai root
4. Konfigurasi gadget USB jadi RNDIS + ADB
5. Rename `rndis0` → `usb0` / `usb1` (nama kosong pertama)
6. Aktifkan ICS `Ethernet` → `Ethernet 2`
7. Verifikasi `usb0` + `play.google.com`

### 3. Verifikasi manual

```powershell
adb shell ip -o addr show usb0
adb shell curl -sS -o /dev/null -w "HTTP=%{http_code}\n" https://play.google.com
adb shell dumpsys connectivity | findstr DnsAddresses
```

Output yang diharapkan: `usb0` dapat IP `192.168.137.x`, DNS `192.168.137.1`, HTTP `302`.

---

## Cara kerja (singkat)

1. **Configfs USB** diubah jadi `gsi.rndis` + `ffs.adb`, VID/PID `05C6:9024` (nilai ini diambil dari `init.qcom.usb.rc` ROM untuk komposisi `rndis_adb`).
2. UDC `<udc>` di-unbind lalu di-bind ulang agar gadget aktif.
3. Antarmuka `rndis0` **di-rename jadi `usb0`** (atau `usb1` kalau `usb0` masih dipakai antarmuka stale dari sesi sebelumnya).
4. ROM memiliki filter `EthernetTracker: (usb|eth)\d+`, sehingga `usb0` dikenali sebagai **jaringan Ethernet**.
5. Android menjalankan DHCP → dapat IP `192.168.137.51` dari ICS Windows.
6. Android mendaftarkan Network dengan DNS `192.168.137.1`, kapabilitas `NOT_VPN`, `INTERNET`, `VALIDATED`.
7. ICS Windows melakukan NAT dari `192.168.137.0/24` ke koneksi internet PC.

Kenapa ini penting: di Android 14+, `setprop net.dns1` **diabaikan** dan `ndc resolver setnetdns` **sudah dihapus**. Dengan menjadi jaringan Ethernet, DNS diatur otomatis lewat DHCP — tidak perlu trik iptables.

Detail teknis ada di [`docs/TECHNICAL.md`](docs/TECHNICAL.md).

---

## Struktur file

| File | Fungsi |
|---|---|
| `rndis-tethering.cmd` | **Entrypoint** — aktifkan reverse tethering RNDIS |
| `restore-default.cmd` | Kembalikan PC & HP ke kondisi awal |
| `reverse-tethering.cmd` | Fallback: Gnirehtet (VPN) |
| `tools/rndis_setup.sh` | Script sisi HP: configfs, rebind, rename `usb0` |
| `tools/enable_ics.vbs` | Aktifkan ICS Windows via COM |
| `tools/disable_ics.vbs` | Matikan ICS Windows |
| `tools/platform-tools/` | ADB |
| `gnirehtet/` | Binary + APK Gnirehtet (cadangan) |
| `docs/TECHNICAL.md` | Catatan teknis & temuan perangkat |

---

## Troubleshooting

### ADB `offline` / tidak muncul

Sering terjadi setelah gadget USB berganti mode. Re-enumerasi perangkat:

```powershell
$d = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*ADB Interface*' -and $_.Status -eq 'OK' } | Select-Object -First 1
Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false
Start-Sleep 2
Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false
adb kill-server; adb start-server
adb devices
```

`rndis-tethering.cmd` sudah melakukan ini otomatis.

### HP reboot / kabel dicabut

Semua konfigurasi RNDIS bersifat runtime. Setelah reboot, `persist.sys.usb.config=adb` memulihkan mode ADB normal. **Jalankan ulang `rndis-tethering.cmd`.**

### DNS tidak jalan

1. Pastikan adapter **Ethernet 2** (Remote NDIS) muncul di `Get-NetAdapter`.
2. Pastikan ICS aktif: `Get-Service SharedAccess`.
3. Cek di HP: `adb shell ip -o addr show usb0` harus ada IP `192.168.137.x`.
4. Cek `adb shell dumpsys connectivity | findstr DnsAddresses` harus ada `192.168.137.1`.

### Play Store tetap error

Pastikan tidak ada VPN aktif:

```powershell
adb shell dumpsys connectivity | findstr /i "VPN CONNECTED"
adb shell su -c "ip -o addr show tun0"
```

Kalau `tun0` masih ada, matikan:

```cmd
cd gnirehtet\gnirehtet-rust-win64
set PATH=..\..\tools\platform-tools;%PATH%
gnirehtet.exe stop REDACTED_SERIAL
```

---

## Kembalikan kondisi awal

```cmd
restore-default.cmd
```

Lalu:
- Cabut kabel atau reboot HP (USB kembali ke mode `adb`)
- Opsional: uninstall **Gnirehtet** lewat Settings → Apps agar izin VPN hilang

Detail perubahan sistem ada di [`docs/TECHNICAL.md#dampak-perubahan`](docs/TECHNICAL.md#dampak-perubahan).

---

## Catatan

Proyek ini spesifik untuk perilaku ROM Android/Qualcomm pada perangkat di atas. Perangkat lain mungkin punya filter `EthernetTracker`, fungsi configfs, atau VID/PID yang berbeda — sesuaikan `tools/rndis_setup.sh`.

Gunakan dengan risiko sendiri. Seluruh perubahan dapat dikembalikan seperti dijelaskan di atas.

## Lisensi

MIT — bebas dipakai dan dimodifikasi.
