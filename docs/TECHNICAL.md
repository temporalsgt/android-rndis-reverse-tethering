# Catatan Teknis — Reverse Tethering RNDIS (universal)

Dokumen ini menjelaskan **mekanisme umum** yang dipakai repo, bukan konfigurasi
khusus satu model HP. Nilai perangkat (UDC, VID/PID, nama antarmuka, dll.)
**dideteksi saat runtime** oleh `tools/rndis_setup.sh` dan `tools/ics.ps1`.
Contoh hasil dari satu perangkat ada di lampiran di bawah sebagai referensi.

---

## 1. Ide dasar

Android modern (14+) mengabaikan trik DNS lama:

| Cara lama | Hasil umum |
|---|---|
| `setprop net.dns1 ...` | Properti berubah, resolver mengabaikan |
| `ANDROID_DNS_MODE=local` | Tidak membantu |
| `ndc resolver setnetdns ...` | Perintah dihapus / `Command not recognized` |
| `iptables` DNAT port 53 | Jalan, tapi bergantung jaringan seluler tetap hidup |

Solusinya: **jangan mengatur DNS manual**. Buat Android melihat koneksi ini sebagai
**Ethernet**, maka DHCP akan memberikan IP + DNS secara otomatis dan Android
mendaftarkan jaringan dengan kapabilitas `INTERNET`, `NOT_VPN`, `VALIDATED`.

Rantai mereka:

```
PC internet ──(ICS / NAT)── RNDIS gadget ── usbN/ethN ── Android EthernetTracker
                                                    └─ DHCP 192.168.137.x
                                                    └─ DNS  192.168.137.1
```

---

## 2. Deteksi sisi Android

Script `rndis_setup.sh` tidak mengandung konstanta perangkat.

### 2.1 Gadget & config node

```
/config/usb_gadget/*        -> pilih yang punya configs/ dan functions/
$G/configs/*                -> config node aktif (biasanya b.1)
$G/functions/*              -> cari fungsi rndis* dan *adb*
```

Prioritas nama fungsi RNDIS: `gsi.rndis`, `rndis`, `rndis.rndis`,
`rndis_bam.rndis`, `f_rndis`, `rndis.gs`, lalu fallback apa pun yang mengandung
`rndis`. Untuk ADB: `ffs.adb`, `adb`, `function_adb`.

### 2.2 UDC

```
cat $G/UDC                  -> nilai saat ini (paling akurat)
ls /sys/class/udc | head -1 -> fallback
```

### 2.3 VID/PID

Nilai `idVendor`/`idProduct` yang sudah ada **dipertahankan**. RNDIS adalah class
USB, sehingga Windows memuat driver *Remote NDIS Compatible Device* berdasarkan
interface class, bukan VID/PID tertentu.

### 2.4 Rebind

```sh
echo "" > $G/UDC
sleep 2
echo "$UDC" > $G/UDC
```

Ini harus dijalankan **di dalam HP sebagai background process**, karena koneksi
ADB putus sejenak saat UDC di-unbind. Setelah itu script menunggu antarmuka
`rndis*`, `usb*`, atau `eth*` muncul maksimal 40 detik.

---

## 3. Deteksi antarmuka & EthernetTracker

Beberapa ROM hanya mengenali nama antarmuka yang cocok dengan filter
EthernetTracker (umumnya `(usb|eth)\d+`). Script:

1. Memakai antarmuka yang muncul.
2. Cek `dumpsys connectivity` untuk baris dengan
   `InterfaceName: <if>` **dan** `Transports: ETHERNET`.
3. Jika belum terdaftar, rename ke `usb0`, `usb1`, … atau `eth0`, `eth1`, …
   (nama kosong pertama), lalu cek lagi.

Nama lama yang "stale" tidak bisa dihapus lewat `ip link del` pada netdev gadget,
makanya script mencari nama kosong berikutnya, bukan selalu `usb0`.

Urutan pemilihan nama sengaja **`usb1…usb7` dulu, `usb0` terakhir**. Pada sebagian
ROM, `usb0` ditandai sebagai *"Interface used for tethering"* sehingga Android
menjalankan sisi server tethering, bukan DHCP client — akibatnya tidak pernah
mendapat IP dari ICS. Memakai `usb1`/`usb2` menghindari konflik ini dan tetap cocok
dengan filter `(usb|eth)\d+`.

DHCP ditunggu dengan loop sampai `ip -o addr show dev <if>` menghasilkan alamat
IPv4 — bukan `sleep` tetap.

---

## 4. Deteksi sisi Windows (ICS)

`New-NetNat` sering tidak tersedia; satu-satunya jalan adalah ICS lewat COM
`HNetCfg.HNetShare.1`. Script `tools/ics.ps1`:

- **Public adapter**: `Get-NetRoute 0.0.0.0/0` dengan metrik terendah
  (fallback: adapter `Up` pertama yang bukan RNDIS). Bisa dioverride `-PublicName`.
- **Private adapter**: `Get-NetAdapter` dengan deskripsi/nama `RNDIS|Remote NDIS`
  (fallback: kosong saat disable). Bisa dioverride `-PrivateName`.
- Mapping ke `EnumEveryConnection` + `NetConnectionProps($conn).Name`.

Nilai `EnableSharing` counter-intuitive di Windows:

```
EnableSharing(0) = public (internet)
EnableSharing(1) = private (dibagikan)
DisableSharing() = matikan
```

Service `SharedAccess` diatur ke `Manual` + `Running` saat enable, dan
**sengaja tidak dinonaktifkan** saat restore.

Apabila adapter RNDIS belum muncul sebagai *Remote NDIS Compatible Device*,
periksa VID/PID/function gadget di log HP dan driver Windows.

---

## 5. ADB & otorisasi

- ADB dicari berurutan: `tools/platform-tools/`, `PATH`, `%USERPROFILE%\platform-tools`,
  `C:\platform-tools`, `%ProgramFiles%\platform-tools`.
- Serial: argumen CLI → `ANDROID_SERIAL` → `DEVICE_SERIAL` → perangkat pertama
  dengan status `device`.
- Setelah UDC di-rebind, Android bisa menganggap koneksi sebagai host baru dan
  memunculkan dialog *Allow USB debugging*. Script menunggu status `unauthorized`
  hilang maksimal ~1 menit. Biasanya cukup tekan *Allow* sekali.

Kunci ADB tersimpan di `%USERPROFILE%\.android\adbkey{,.pub}` dan tetap stabil
walau server ADB di-restart (`adb kill-server && adb start-server`).

---

## 6. Dampak & revert

| Objek | Sifat | Revert |
|---|---|---|
| configfs symlink / UDC / VID-PID | Runtime | Reboot HP atau `restore-default.cmd` |
| Interface `usbN` + IP DHCP | Runtime | Cabut kabel / reboot HP |
| SELinux permissive | Runtime, sebentar | Dikembalikan ke nilai awal oleh script |
| ICS sharing | Persisten sampai dimatikan | `restore-default.cmd` |
| Service `SharedAccess` | Manual/Running | Dibiarkan (tidak di-disable) |
| File `/data/local/tmp/rndis_setup.*` | Sementara | Dihapus `restore-default.cmd` |
| Data seluler | Tidak disentuh | — |

Tidak menyentuh `/system`, `/vendor`, sepolicy, `build.prop`, atau modul root.

### 7.1 Fungsi USB lain dan pemulihannya

Karena configfs disusun ulang menjadi RNDIS + ADB, **MTP/PTP/MIDI dan USB tethering
bawaan Android tidak aktif** selama sesi. Ini konsekuensi metode, bukan bug.

`restore-default.cmd` mematikan ICS dan menurunkan antarmuka, tetapi **tidak** mengubah
kembali komposisi gadget secara aktif. Cara paling aman untuk memulihkan semua fungsi USB
adalah **cabut kabel atau reboot HP**. Setelah itu `persist.sys.usb.config=adb`
(mode bawaan) dipakai lagi dan MTP/PTP/MIDI bisa dipilih dari notifikasi USB.

**Catatan insiden audit.** Saat pengujian pernah ditambahkan handler ADB `offline`
yang memanggil `Disable-PnpDevice` pada *ADB Interface* Windows. Ini membuat perangkat
berhenti ter-enumerasi (`USB\VID_0000&PID_0002`, *Device Descriptor Request Failed*)
dan harus dipulihkan dengan reboot HP. Kode tersebut **sudah dihapus** sebelum commit;
handler `offline` sekarang hanya melakukan `adb kill-server`/`start-server`/`reconnect`.
Jangan memperkenalkan kembali `Disable-PnpDevice` di sini.

---

## 7. Batasan kompatibilitas

- Perangkat wajib punya configfs USB gadget dan fungsi RNDIS. Beberapa ROM hanya
  menyediakan `ncm`/`ecm` — belum didukung script ini.
- Filter EthernetTracker berbeda-beda; mekanisme rename `usbN`/`ethN` mencakup
  yang umum, tapi perlu disesuaikan bila ROM memakai pola lain
  (cek `dumpsys ethernet`).
- Beberapa gadget HAL mengulang konfigurasi saat jaringan berubah sehingga ADB
  bisa `offline`/`unauthorized` sementara — sudah di-handle dengan retry.

---

## Lampiran A — Contoh hasil deteksi (referensi, bukan konstanta)

Perangkat yang dipakai saat pengembangan awal: Android 17, USB Gadget HAL
(`configfs=2`), controller `<udc>`, fungsi `gsi.rndis` + `ffs.adb`.
Contoh log:

```
gadget=/config/usb_gadget/g1
config=/config/usb_gadget/g1/configs/b.1
rndis_fn=gsi.rndis
adb_fn=ffs.adb
udc=<udc>
vidpid=0x05C6:0x9024 (dari init.qcom.usb.rc)
antarmuka=usb0
addr=192.168.137.151/24
dns=DnsAddresses: [ /192.168.137.1 ]
ethernet=yes
```

Contoh NetworkAgent:

```
ni{Ethernet CONNECTED ...}
Transports: ETHERNET
Capabilities: NOT_METERED & INTERNET & NOT_RESTRICTED & TRUSTED & NOT_VPN & VALIDATED
DnsAddresses: [ /192.168.137.1 ]
Routes: [ 0.0.0.0/0 -> 192.168.137.1 usb0 ]
```

Nilai-nilai di atas **hanya contoh**. Script tidak menuliskan nilai apa pun di atas sebagai konstanta.

---

## Referensi

- [XDA: Has Android 14 crippled the ndc command?](https://xdaforums.com/t/has-android-14-crippled-the-ndc-command.4645821/)
- AOSP DNS Resolver module — `source.android.com/docs/core/ota/modular-system/dns-resolver`
- Android configfs gadget docs — `source.android.com/docs/core/connect/usb-gadget`
