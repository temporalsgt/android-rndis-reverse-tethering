# Reverse Tethering — PC Windows → Android (RNDIS / Ethernet)

Berbagi koneksi internet **PC Windows** ke **perangkat Android apa pun** lewat kabel USB,
tanpa app VPN dan tanpa memasang modul tambahan — cukup **akses root (`su`)** dan
**USB debugging**.

Antarmuka USB dibuat menjadi **RNDIS**, lalu Android mendaftarkannya sebagai
**jaringan Ethernet** (`TRANSPORT_ETHERNET`), bukan VPN. Hasilnya: Google Play,
ping/ICMP, dan DNS berfungsi normal, serta **data seluler tidak diperlukan**.

> Repo ini sengaja **universal**: tidak ada serial, model, vendor, UDC, VID/PID,
> maupun nama adapter yang di-hardcode. Semuanya dideteksi saat runtime.

---

## Prasyarat

| Pihak | Syarat |
|---|---|
| HP/Android | Root dengan `su` yang bisa dieksekusi lewat ADB, USB debugging aktif, kabel USB data |
| Sistem Android | Mendukung **USB gadget configfs** (`/config/usb_gadget/<n>/`) dan memiliki fungsi **RNDIS** (mis. `gsi.rndis`, `rndis`, `rndis.rndis`) serta ADB (`ffs.adb`) |
| PC | Windows dengan hak **Administrator** dan koneksi internet aktif |
| ADB | Tersedia di salah satu: `tools/platform-tools/`, `PATH`, `%USERPROFILE%\platform-tools\`, `C:\platform-tools\`, atau `%ProgramFiles%\platform-tools\` |
| Windows | Service `SharedAccess` (ICS) — script akan mengaturnya ke `Manual` + `Running` |

Binary ADB **tidak disertakan** di repo (terkena `.gitignore`). Siapkan sendiri
atau taruh `adb.exe` di `tools/platform-tools/`.

Metode fallback Gnirehtet (VPN) opsional; binary tidak ikut ter-clone.

---

## Cara pakai

```cmd
rndis-tethering.cmd
```

Atau tentukan perangkat secara eksplisit:

```cmd
rndis-tethering.cmd REDACTED_SERIAL
```

Serial juga bisa diambil dari environment `ANDROID_SERIAL` atau `DEVICE_SERIAL`.

Yang dilakukan script:

1. Cari ADB (repo → `PATH` → lokasi umum) dan tentukan serial otomatis.
2. Tunggu otorisasi USB debugging bila muncul dialog di HP.
3. Cek root `su`, lalu aktifkan service ICS Windows.
4. Deteksi di HP: gadget configfs, config node, fungsi RNDIS/ADB, UDC, VID/PID.
5. Susun gadget jadi RNDIS + ADB, rebind UDC, lalu deteksi antarmuka jaringan.
6. Jika belum dikenal sebagai Ethernet, rename ke `usbN`/`ethN` (filter EthernetTracker umum).
7. Tunggu DHCP dari ICS (bukan sleep tetap).
8. Aktifkan ICS dengan mencari adapter internet (default route) dan adapter RNDIS secara otomatis.
9. Verifikasi IP, HTTP `play.google.com`, dan tampilkan log dari HP.

---

## Verifikasi manual

```powershell
adb shell "ip -o addr show"
adb shell "curl -sS -o /dev/null -w 'HTTP=%{http_code}\n' --max-time 15 https://play.google.com"
adb shell "dumpsys connectivity | grep DnsAddresses"
```

Yang diharapkan: antarmuka `usbN`/`ethN`/`rndisN` mendapat IP dari `192.168.137.0/24`,
DNS `192.168.137.1`, `TRANSPORT_ETHERNET`, `NOT_VPN`, `VALIDATED`, HTTP `302`.

Log lengkap hasil deteksi ada di HP:

```powershell
adb shell cat /data/local/tmp/rndis_setup.log
```

---

## Kembalikan kondisi awal

```cmd
restore-default.cmd
```

Script ini **hanya** mematikan ICS, menurunkan antarmuka RNDIS, menghentikan Gnirehtet,
dan membersihkan file sementara. Service `SharedAccess` sengaja dibiarkan dalam keadaan
`Manual` (tidak dinonaktifkan permanen), dan **data seluler tidak diubah**.

Setelah itu cabut kabel atau reboot HP agar USB kembali ke mode ADB normal.

---

## Struktur

| File | Fungsi |
|---|---|
| `rndis-tethering.cmd` | Entrypoint utama — deteksi otomatis + aktifkan RNDIS & ICS |
| `tools/rndis_setup.sh` | Sisi HP: deteksi gadget/UDC/fungsi, rebind, rename, tunggu DHCP |
| `tools/ics.ps1` | Sisi PC: aktifkan/nonaktifkan ICS dengan deteksi adapter otomatis |
| `restore-default.cmd` | Kembalikan kondisi awal |
| `reverse-tethering.cmd` | Fallback opsional via Gnirehtet (VPN) |
| `docs/TECHNICAL.md` | Penjelasan mekanisme, kompatibilitas, dan batasan |

---

## Troubleshooting

**ADB `unauthorized` setelah gadget di-rebind**
Wajar — tekan *Allow* di layar HP (centang *Always allow from this computer*).
Script sudah menunggu dan retry otomatis.

**"fungsi RNDIS/ADB tidak ditemukan"**
Lihat daftar fungsi di log. ROM harus punya fungsi bertema `rndis`. Beberapa ROM
memakai `ncm`/`ecm` sebagai ganti RNDIS; script ini belum menangani fungsi tersebut.

**"configfs usb_gadget tidak ditemukan"**
Perangkat tidak mendukung USB configfs, atau belum ter-mount. Script tidak bisa
berjalan tanpa ini.

**IP `192.168.137.x` tidak muncul**
- Pastikan adapter RNDIS muncul di `Get-NetAdapter` (deskripsi *Remote NDIS Compatible Device*).
- Pastikan `SharedAccess` berstatus `Running`.
- Cek log HP: baris `addr=` dan `ethernet=` harus terisi / `yes`.
- Beberapa ROM tidak memakai filter `(usb|eth)\d+`; lihat `dumpsys ethernet` pada HP
  dan sesuaikan prefix rename di `rndis_setup.sh` bila perlu.
- Script menghindari `usb0` sampai opsi terakhir karena pada sebagian ROM nama itu
  dipakai Android sebagai *interface tethering* (DHCP client tidak jalan).

**ICS gagal dengan "adapter public/private sama"**
Tentukan eksplisit:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\ics.ps1 -Action Enable -PublicName "Ethernet" -PrivateName "Ethernet 2"
```

**Play Store tetap error / terdeteksi VPN**
Pastikan tidak ada `tun0` dan jaringan aktif bertipe `ETHERNET`:

```powershell
adb shell "ip -o addr show tun0"
adb shell "dumpsys connectivity | grep -i 'Transports: ETHERNET'"
```

---

## Kompatibilitas & batasan

- Sudah diuji di Android 17 dengan USB Gadget HAL (`configfs=2`), namun mekanismenya
  umum untuk Android dengan configfs + fungsi RNDIS.
- Perubahan di HP bersifat **runtime** (hilang saat reboot/cabut kabel).
- `setenforce 0` hanya dilakukan selama setup lalu dikembalikan ke nilai awal.
- Tidak menyentuh `/system`, `/vendor`, sepolicy, build.prop, atau modul root.
- Gnirehtet (fallback) memakai VPN dan lebih sering bermasalah di Play Store.

---

## Lisensi

MIT — bebas dipakai dan dimodifikasi. Gunakan dengan risiko sendiri.
