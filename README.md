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
| ADB | **Platform-tools lengkap sudah disertakan** di `tools/platform-tools/`. Tidak perlu install terpisah |
| Windows | Service `SharedAccess` (ICS) — script akan mengaturnya ke `Manual` + `Running` |

Seluruh isi *SDK Platform Tools* untuk Windows sudah ikut di repo di folder
`tools\platform-tools\` — bukan hanya `adb.exe`, tapi juga `fastboot.exe`,
`sqlite3.exe`, DLL pendukung, `NOTICE.txt`, dan utilitas lainnya. Script akan
memakai ADB dari folder ini lebih dulu; tidak perlu download atau menambahkan ke `PATH`.

---

## Dapatkan file repo (tanpa Git juga bisa)

Cara paling gampang: **Download ZIP** — tidak perlu install Git, GitHub CLI, atau login.

1. Buka <https://github.com/temporalsgt/android-rndis-reverse-tethering>
2. Klik tombol hijau **<> Code** → **Download ZIP**.
3. Ekstrak ke folder mana pun, misalnya `C:\Users\<Anda>\Documents\Android-RNDIS`.

Kalau sudah punya Git dan lebih suka clone:

```cmd
git clone https://github.com/temporalsgt/android-rndis-reverse-tethering.git
```

Itu saja — **tidak perlu** `gh auth login` atau `git pull` untuk memakai repo ini.

### ADB (platform-tools sudah disertakan lengkap)

Tidak perlu install atau download apa pun. Seluruh isi platform-tools ada di
`tools\platform-tools\` (`adb.exe`, `fastboot.exe`, DLL, utilitas, `NOTICE.txt`).
Cek opsional:

```cmd
tools\platform-tools\adb.exe version
```

---

## Cara pakai (langkah demi langkah)

### Persiapan

1. **ADB.** Sudah disertakan di `tools\platform-tools\` — tidak perlu install.
   Cek opsional: `tools\platform-tools\adb.exe version`.
2. **HP:** aktifkan **Developer options → USB debugging**, dan pastikan ada akses
   **root (`su`)** yang bisa dipanggil dari ADB.
3. **Kabel:** gunakan kabel USB **data** (bukan hanya charging), hubungkan ke PC.
4. **PC:** buka **CMD/PowerShell sebagai Administrator** (klik kanan → *Run as
   administrator*). Hak admin wajib karena script mengatur ICS Windows.
5. Saat HP menampilkan dialog *Allow USB debugging*, tekan **Allow / Izinkan**
   (centang *Always allow from this computer*).

### Jalankan

Buka terminal **sebagai Administrator** di folder hasil ekstrak repo:

```cmd
cd /d <folder hasil ekstrak>
```

**Cek perangkat terdeteksi**

```cmd
adb devices
```

Harus muncul seperti:

```text
List of devices attached
ABC123XYZ789    device
```

Kalau statusnya `unauthorized` → tekan *Allow* di HP lalu ulangi.
Kalau **kosong** → cabut–pasang kabel, ganti port/kabel, atau reboot HP.

**Jalankan tethering**

```cmd
rndis-tethering.cmd
```

> Kalau dijalankan dengan **double-click**, klik kanan dulu file-nya dan pilih
> **Run as administrator** — kalau tidak, script akan berhenti di pengecekan hak admin.
> Jendela akan tetap terbuka dan meminta menekan sembarang tombol di akhir, supaya
> pesan error sempat dibaca.

Kalau ada beberapa HP terhubung, tentukan serialnya:

```cmd
rndis-tethering.cmd ABC123XYZ789
```

Atau lewat environment variable:

```cmd
set ANDROID_SERIAL=ABC123XYZ789
rndis-tethering.cmd
```

**Tunggu sampai selesai (±40–60 detik)**

Output yang menandakan sukses:

```text
[0/6] Cek perangkat dan root...
Root: OK
[1/6] Aktifkan service ICS Windows...
[2/6] Kirim setup script ke HP (/data/adb/rndis_setup.sh)...
[3/6] Jalankan setup di HP sebagai root...
[4/6] Tunggu gadget + DHCP...
[5/6] Aktifkan ICS (deteksi adapter otomatis)...
ICS aktif: Ethernet -> Ethernet 2
[6/6] Verifikasi...
HTTP=302 time=0.15s
```

Kalau muncul `WARNING: IP ICS belum muncul`, lihat log HP yang ditampilkan di bawahnya;
biasanya ada keterangan di baris `addr=` / `ethernet=`.

**Pakai internet di HP**

Buka browser atau Play Store. Coba **matikan data seluler** — internet harus tetap jalan
karena sekarang lewat kabel (Ethernet). Jangan heran kalau MTP/PTP/MIDI tidak aktif;
lihat catatan di bawah.

**Selesai / kembali ke awal**

```cmd
restore-default.cmd
```

Lalu **cabut kabel atau reboot HP**, dan pilih *File transfer (MTP)* di notifikasi USB
kalau mau transfer file lagi.

---

### Mendapatkan serial (biasanya tidak perlu)

Kalau hanya satu HP terhubung, script otomatis memakai serial itu — Anda **tidak perlu**
mencarinya. Serial diperlukan hanya kalau ada beberapa perangkat terhubung atau ingin
menentukan perangkat secara eksplisit.

Cara mendapatkannya:

**1. Lewat ADB (paling cepat, saat HP sudah terhubung & diizinkan):**

```cmd
adb devices
```

Output:

```text
List of devices attached
ABC123XYZ789    device
```

Kolom pertama (`ABC123XYZ789`) itu serialnya. Kalau statusnya `unauthorized`, serialnya
tetap terlihat — cukup tekan *Allow* di layar HP.

Bisa juga dari dalam perangkat:

```cmd
adb shell getprop ro.serialno
```

**2. Tanpa ADB — dari HP:**
Buka **Settings → About phone → Model & hardware / Serial number**.

**3. Tanpa ADB — dari Windows:**
Device Manager → *Android Phone / ADB Interface* →
tab **Details** → properti **Device instance path**. Serial adalah bagian setelah
backslash terakhir, misalnya `USB\VID_xxxx&PID_yyyy\ABC123XYZ789`.

> Contoh di atas hanya placeholder. Jangan pakai `emulator-5554` untuk perangkat fisik.

### Apa yang terjadi di belakang layar

1. Pakai ADB dari `tools\platform-tools\` (fallback: `PATH` → lokasi umum) dan tentukan serial otomatis.
2. Tunggu otorisasi USB debugging bila muncul dialog di HP.
3. Cek root `su`, lalu aktifkan service ICS Windows.
4. Deteksi di HP: gadget configfs, config node, fungsi RNDIS/ADB, UDC, VID/PID.
5. Susun gadget jadi RNDIS + ADB, rebind UDC, lalu deteksi antarmuka jaringan.
6. Rename antarmuka ke `usbN`/`ethN` agar dikenal sebagai Ethernet (filter EthernetTracker umum).
7. Tunggu DHCP dari ICS (bukan sleep tetap).
8. Aktifkan ICS dengan mencari adapter internet (default route) dan adapter RNDIS secara otomatis.
9. Verifikasi IP, HTTP `play.google.com`, dan tampilkan log dari HP.

Script sisi HP ditempatkan di `/data/adb/` bila direktori root-only itu tersedia;
jika tidak, fallback ke `/data/local/tmp/` (keduanya dibersihkan oleh `restore-default.cmd`).

---

## Verifikasi manual

```powershell
adb shell "ip -o addr show"
adb shell "if command -v curl >/dev/null 2>&1; then curl -sS -o /dev/null -w 'HTTP=%{http_code}\n' --max-time 15 https://play.google.com; elif command -v wget >/dev/null 2>&1; then wget -q -O /dev/null -S --timeout=15 https://play.google.com 2>&1 | grep -m1 HTTP; else echo NO_HTTP_CLIENT; fi"
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

Script ini **hanya** mematikan ICS, menurunkan antarmuka RNDIS,
dan membersihkan file sementara. Service `SharedAccess` sengaja dibiarkan dalam keadaan
`Manual` (tidak dinonaktifkan permanen), dan **data seluler tidak diubah**.

Setelah itu cabut kabel atau reboot HP agar USB kembali ke mode ADB normal.

> **Penting — fungsi USB lain:** saat RNDIS aktif, gadget USB dipakai penuh untuk
> **RNDIS + ADB**. Karena itu **MTP (transfer file), PTP, MIDI, dan USB tethering bawaan
> Android tidak tersedia** selama sesi. Ini disengaja oleh metode ini, bukan kerusakan.
> Setelah `restore-default.cmd`, **cabut kabel atau reboot HP** agar komposisi gadget
> kembali ke `adb` dan Anda bisa memilih MTP/PTP/MIDI lagi dari notifikasi USB HP.
>
> `restore-default.cmd` saat ini **belum** melakukan reset gadget secara aktif; reboot
> masih merupakan cara paling aman untuk memulihkan seluruh fungsi USB.

---

## Struktur

| File | Fungsi |
|---|---|
| `rndis-tethering.cmd` | Entrypoint utama — deteksi otomatis + aktifkan RNDIS & ICS |
| `restore-default.cmd` | Kembalikan kondisi awal |
| `check-usb.cmd` | Cek kondisi USB (Windows + HP) + kesimpulan mode |
| `tools/rndis_setup.sh` | Sisi HP: deteksi gadget/UDC/fungsi, rebind, rename, tunggu DHCP |
| `tools/ics.ps1` | Sisi PC: aktifkan/nonaktifkan ICS dengan deteksi adapter otomatis |
| `tools/usb_status.ps1` | Mesin pemeriksa status USB yang dipanggil `check-usb.cmd` |
| `tools/usb_status_termux.sh` | Versi bash dijalankan **di HP lewat Termux** |
| `docs/TECHNICAL.md` | Penjelasan mekanisme, kompatibilitas, dan batasan |

### Penjelasan tiga file CMD

`rndis-tethering.cmd` dan `restore-default.cmd` memiliki pola yang sama: cari `adb.exe`
(`tools\platform-tools\` → `PATH` → lokasi umum), tentukan serial
(argumen → `ANDROID_SERIAL`/`DEVICE_SERIAL` → perangkat pertama yang `device`),
lalu menjalankan tugasnya. `check-usb.cmd` hanya wrapper tipis untuk
`tools\usb_status.ps1` yang melakukan pemeriksaan read-only.

#### 1. `rndis-tethering.cmd` — file utama

Yang paling sering dipakai. Wajib dijalankan sebagai **Administrator**.

| Tahap | Apa yang dilakukan |
|---|---|
| Cek awal | Cek hak admin, cari ADB, tentukan serial, tunggu status `device` (retry `unauthorized` / `offline`), cek root `su` |
| `[1/6]` | Nyalakan service Windows `SharedAccess` (ICS), di-set `Manual` |
| `[2/6]` | Push `tools\rndis_setup.sh` ke HP — ke `/data/adb/` bila ada, else `/data/local/tmp/` — lalu `chmod 755` |
| `[3/6]` | Jalankan script itu di HP sebagai root, di **background** (karena ADB putus saat USB di-rebind) |
| `[4/6]` | Tunggu gadget USB + DHCP diberikan Windows |
| `[5/6]` | Panggil `tools\ics.ps1 -Action Enable` (adapter internet & RNDIS dideteksi otomatis) |
| `[6/6]` | Verifikasi: baca antarmuka dari log HP, cek IP `192.168.137.x` (retry), cek HTTP via `curl`/`wget`, tampilkan log HP |

Contoh pemakaian:

```cmd
rndis-tethering.cmd
rndis-tethering.cmd ABC123XYZ789
```

Exit code `0` = selesai (cek baris `HTTP=`), `1` = gagal pada tahap awal/ICS.

#### 2. `restore-default.cmd` — pemulih

Dijalankan setelah selesai memakai tethering. Juga mencari ADB & serial seperti di atas.

| Tahap | Apa yang dilakukan |
|---|---|
| `[1/3]` | Panggil `ics.ps1 -Action Disable` untuk mematikan ICS |
| `[2/3]` | Turunkan antarmuka RNDIS di HP — nama dibaca dari `rndis_setup.log`; kalau log tidak ada, coba daftar nama umum |
| `[3/3]` | Hapus script/log sementara di HP |

**Sengaja tidak dilakukan:** mematikan permanen service `SharedAccess`, mengubah data
seluler, atau memaksa mode USB. Karena itu, setelah menjalankan ini Anda tetap perlu
**cabut kabel atau reboot HP** supaya komposisi gadget kembali ke `adb` dan MTP/PTP/MIDI
bisa dipakai lagi.

Contoh:

```cmd
restore-default.cmd
```

#### 3. `check-usb.cmd` — cek kondisi USB

Menampilkan informasi dari **Windows dan HP sekaligus**, lalu memberi kesimpulan.
Tidak mengubah apa pun (read-only), jadi aman dipakai kapan saja.

```cmd
check-usb.cmd
check-usb.cmd <SERIAL>
```

Kalau dijalankan dengan **double-click** dari File Explorer, jendela akan tetap terbuka
dan meminta menekan sembarang tombol di akhir — ini supaya hasilnya sempat dibaca.
Kalau dijalankan dari terminal yang sudah terbuka, cukup tekan Enter saat diminta.

Yang ditampilkan:

- **ADB**: binary yang dipakai, serial dan status (`device` / `unauthorized` / `offline`).
- **Android**: `persist.sys.usb.config`, `sys.usb.config`, fungsi USB, antarmuka
  `usbN`/`ethN`, IP `192.168.137.x`, `EthernetTracker`, isi configfs (UDC/config/VID/PID),
  dan baris penting dari log sesi terakhir.
- **Windows**: device USB yang ter-enumerasi + VID/PID, adapter Remote NDIS beserta IP,
  status service `SharedAccess`, dan koneksi ICS yang aktif.
- **Kesimpulan**, salah satu dari:
  - `MODE RNDIS / reverse tethering SEDANG AKTIF`
  - `KONDISI TRANSISI: ada jejak RNDIS tapi belum aktif penuh`
  - `MODE NORMAL (ADB/MTP) - belum masuk RNDIS`

Contoh potongan hasil:

```text
=== KESIMPULAN ===
MODE NORMAL (ADB/MTP) - belum masuk RNDIS.
Catatan: persist.sys.usb.config = 'mtp,adb' (bawaan: 'adb').
```

### Cek dari HP (Termux)

Kalau ingin memeriksa langsung dari perangkat, pakai `tools/usb_status_termux.sh`.
Skrip ini **read-only** dan bisa jalan dengan `sh` maupun `bash`.

Salin ke HP lewat ADB:

```cmd
adb push tools\usb_status_termux.sh /sdcard/Download/usb-status.sh
```

Lalu di Termux:

```sh
bash /sdcard/Download/usb-status.sh
```

Atau download langsung di Termux (butuh `curl`/`wget`):

```sh
curl -L -o usb-status.sh \
  https://raw.githubusercontent.com/temporalsgt/android-rndis-reverse-tethering/master/tools/usb_status_termux.sh
bash usb-status.sh
```

Yang ditampilkan: serial/model/Android, konfigurasi USB, isi configfs (UDC,
nama konfigurasi, VID/PID), antarmuka `usbN` + IP, `EthernetTracker`, DNS, log
sesi terakhir, dan kesimpulan **MODE NORMAL / TRANSISI / MODE RNDIS** yang sama
dengan versi Windows.

> Membaca configfs dan `/data/local/tmp/rndis_setup.log` memerlukan akses root.
> Tanpa `su`, bagian itu ditandai tidak terbaca; sisanya tetap tampil.

---

## Troubleshooting

**ADB `unauthorized` setelah gadget di-rebind**
Wajar — tekan *Allow* di layar HP (centang *Always allow from this computer*).
Script sudah menunggu dan retry otomatis.

**HP tidak muncul / `USB Device Descriptor Request Failed` setelah sesi RNDIS**
Gadget bisa saja masih stuck dalam komposisi RNDIS. Lakukan: cabut–pasang kabel,
coba port/kabel lain, atau **force reboot HP** (Power + Volume Up ~10–15 detik).
Setelah boot, buka notifikasi USB dan pilih *File transfer (MTP)*.
**Jangan menonaktifkan interface ADB lewat Device Manager / PnP** — itu bisa membuat
HP tidak ter-enumerasi sama sekali hingga reboot. Script versi terbaru sudah tidak
lagi melakukan itu.

Cek nilai USB persisten dengan:

```powershell
adb shell getprop persist.sys.usb.config
```

Nilai bawaan adalah `adb`. Bila pernah diubah manual menjadi `mtp,adb` dan ingin
kembali persis seperti semula, set kembali ke `adb` lalu reboot HP.

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
  Perlu dicatat: ini **melemahkan SELinux secara global untuk sementara** (beberapa detik)
  dan memerlukan kernel yang mengizinkan perubahan mode. Pada perangkat produksi/kerja,
  pahami risikonya sebelum menjalankan.
- Tidak menyentuh `/system`, `/vendor`, sepolicy, build.prop, atau modul root.

---

## Lisensi

MIT — bebas dipakai dan dimodifikasi. Gunakan dengan risiko sendiri.
