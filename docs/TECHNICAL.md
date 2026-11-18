# Catatan Teknis — Reverse Tethering RNDIS

Catatan mendetail hasil eksperimen di **Android device (device)**, Android 17, APatch, Windows 10 Pro 19045.

---

## 1. Temuan perangkat

```text
ro.product.model      = Android device
ro.product.device     = device
ro.build.version.release = 17
ro.build.version.sdk  = 37
persist.sys.usb.config = adb
sys.usb.configfs       = 2
vendor.usb.use_gadget_hal = 1
vendor.usb.controller  = <udc>
vendor.usb.rndis.func.name = gsi
persist.vendor.usb.config.extra = none
```

Root: APatch (`/data/adb/ap/bin/resetprop`, `su --help` menampilkan "APatch"). Opsi `su -Z/--context` **diabaikan**, jadi context tetap `u:r:shell:s0`.

---

## 2. Kenapa `setprop sys.usb.config` gagal

```text
init: Unable to set property 'sys.usb.config' from uid:0 ...
SELinux permission check failed
  scontext=u:r:shell:s0
  tcontext=u:object_r:usb_control_prop:s0
```

Meski `uid=0`, context shell tidak diizinkan menulis `usb_control_prop`. `resetprop` dari APatch juga tidak memicu init reconfigure.

Selain itu, blok init untuk `rndis,adb` di `/vendor/etc/init/hw/init.qcom.usb.rc` bersyarat `sys.usb.configfs=1`:

```text
on property:sys.usb.ffs.ready=1 && property:sys.usb.config=rndis,none,adb && property:sys.usb.configfs=1
    write /config/usb_gadget/g1/configs/b.1/strings/0x409/configuration "rndis_adb"
    write /config/usb_gadget/g1/idVendor 0x05C6
    write /config/usb_gadget/g1/idProduct 0x9024
    symlink .../functions/${vendor.usb.rndis.func.name}.rndis .../configs/b.1/f1
    symlink .../functions/ffs.adb .../configs/b.1/f2
    write /config/usb_gadget/g1/UDC ${sys.usb.controller}
```

Karena perangkat memakai `configfs=2` (gadget HAL), blok ini **never dieksekusi**. Itulah sebabnya konfigurasi dilakukan manual lewat configfs.

Nilai VID/PID `05C6:9024` diambil persis dari blok tersebut → Windows mengenalinya sebagai **Remote NDIS Compatible Device** + **ADB Interface** (MI_00 / MI_02) tanpa driver tambahan.

---

## 3. Fungsi configfs yang tersedia

```text
/config/usb_gadget/g1/functions/
  ffs.adb, ffs.mtp, ffs.ptp, ...
  gsi.rmnet
  gsi.rndis      <-- dipakai
  ncm.gs6
  rndis.rndis, rndis_bam.rndis
  mass_storage.0, diag.diag, ...
```

Struktur konfigurasi aktif:

```text
/config/usb_gadget/g1/configs/b.1/
  function0 -> ../../../../usb_gadget/g1/functions/ffs.adb   (awal)
  f1 -> ../../../../usb_gadget/g1/functions/gsi.rndis         (setelah diubah)
  f2 -> ../../../../usb_gadget/g1/functions/ffs.adb
```

Catatan penting: symlink function berada **langsung di `b.1/`**, bukan di `b.1/functions/`. Target relatif `../../../../usb_gadget/g1/functions/...` dihitung dari `b.1/`. Membuat symlink dengan path absolut juga berhasil dan dinormalisasi configfs menjadi bentuk relatif tersebut.

Prosedur rebind harus dijalankan sebagai **proses lokal di HP** (background), karena ADB putus saat UDC di-unbind:

```sh
echo "" > /config/usb_gadget/g1/UDC
sleep 3
echo <udc> > /config/usb_gadget/g1/UDC
```

---

## 4. Windows: ICS lewat COM

`New-NetNat` tidak tersedia di build ini (`MSFT_NetNat` class "Not found" / "Invalid class"), begitu juga fitur RRAS. Satu-satunya jalan: **ICS (Internet Connection Sharing)**.

Di PowerShell, `HNetCfg.HNetShare` sulit dipakai (method `EnumConnections` tidak terekspos). Memakai **VBScript** dengan late binding berhasil:

```vbscript
Set netshare = CreateObject("HNetCfg.HNetShare.1")
Set col = netshare.EnumEveryConnection
For Each conn In col
    Set props = netshare.NetConnectionProps(conn)
    If props.Name = "Ethernet" Then Set pub = conn
    If props.Name = "Ethernet 2" Then Set priv = conn
Next
netshare.INetSharingConfigurationForINetConnection(pub).EnableSharing 0
netshare.INetSharingConfigurationForINetConnection(priv).EnableSharing 1
```

Nilai `EnableSharing` **counter-intuitive**: public = `0`, private = `1` (dokumentasi/implementasi di build ini). Percobaan dengan public=`1`, private=`2` menghasilkan error:

```text
An operation is blocked waiting for an oplock.
```

Service `SharedAccess` awalnya **Disabled** → diaktifkan otomatis oleh script.

---

## 5. Masalah DNS di Android 14+

Semua cara lama **tidak berfungsi** di Android 17:

| Cara | Hasil |
|---|---|
| `setprop net.dns1 192.168.137.1` | Properti berubah, tapi resolver mengabaikan |
| `ANDROID_DNS_MODE=local` | Tidak membantu |
| `ndc resolver setnetdns ...` | `500 0 Command not recognized` |
| `cmd resolver ...` | Hanya "Rotation Resolver", bukan DNS config |
| `ndc network default set ...` | `400 0 setDefaultNetwork() failed` |
| `service call dnsresolver ...` | Butuh Parcel `DnsConfigParcel`, tidak bisa dibangun dari `service call` |

Referensi: [XDA — Has Android 14 crippled the ndc command?](https://xdaforums.com/t/has-android-14-crippled-the-ndc-command.4645821/)

### Workaround pertama (ditinggalkan)

Karena DNS query carrier itu IPv4 (`112.215.198.248/254`), query dialihkan dengan iptables:

```sh
iptables -t nat -A OUTPUT -p udp --dport 53 -j DNAT --to-destination 192.168.137.1:53
iptables -t nat -A OUTPUT -p tcp --dport 53 -j DNAT --to-destination 192.168.137.1:53
ip rule add from all lookup main pref 15000
ip route add default via 192.168.137.1 dev rndis0 onlink
```

Ini **berhasil**, tetapi bergantung pada jaringan internet seluler tetap aktif supaya resolver punya server DNS. Ketika jaringan itu turun, resolver beralih ke DNS IPv6 IMS (`2400:9800:2:2::245`) dan DNAT IPv4 tidak kena → DNS mati.

### Solusi final: jadikan jaringan Ethernet

`dumpsys ethernet` menunjukkan:

```text
Ethernet State: enabled
Ethernet interface name filter: (usb|eth)\d+
```

Jadi `rndis0` di-rename menjadi `usb0`:

```sh
ip link set rndis0 down
ip link set rndis0 name usb0
ip link set usb0 up
```

Android otomatis:
- Mendeteksi `usb0` lewat `EthernetTracker`
- Menjalankan DHCP client → IP `192.168.137.51/24`
- Menerima DNS `192.168.137.1` dari ICS Windows
- Mendaftarkan NetworkAgent dengan kapabilitas:

```text
ni{Ethernet CONNECTED ...}
Transports: ETHERNET
Capabilities: NOT_METERED & INTERNET & INTERNET & NOT_RESTRICTED & TRUSTED & NOT_VPN & VALIDATED
DnsAddresses: [ /192.168.137.1 ]
Routes: [ 0.0.0.0/0 -> 192.168.137.1 usb0 ]
```

Keuntungan:
- DNS diatur sendiri oleh Android (tidak ada `net.dns1`, tidak ada iptables)
- Play Store melihat `TRANSPORT_ETHERNET`, bukan VPN → tidak diblokir
- **Data seluler tidak diperlukan** sama sekali
- Semua protokol IP (ICMP termasuk) lewat kernel

---

## 6. Instabilitas ADB

Setiap kali jaringan/data seluler berubah, USB Gadget HAL (`configfs=2`) mengulang konfigurasi gadget dan kadang menghilangkan interface ADB/RNDIS. Gejala:

```text
(no serial number)    offline
```

Pemulihan: re-enumerasi PnP device ADB (lihat README → Troubleshooting). Ini sudah diotomatisasi di `rndis-tethering.cmd`.

---

## 7. Dampak perubahan

### HP

| Perubahan | Sifat | Cara revert |
|---|---|---|
| App `com.genymobile.gnirehtet` terpasang | Persisten | Uninstall via Settings |
| `appops ACTIVATE_VPN: allow` | Persisten | Hilang saat app di-uninstall |
| `mobile_data = 1` | Persisten | Ubah di Settings / `settings put global mobile_data 0` |
| 20 script di `/data/local/tmp/*.sh` | Persisten (temporary dir) | `adb shell rm /data/local/tmp/*.sh` |
| configfs VID/PID + symlink | Runtime | Reboot |
| `rndis0` → `usb0` + IP DHCP | Runtime | Cabut kabel / reboot |
| SELinux Permissive (saat setup) | Runtime | Dikembalikan ke Enforcing oleh script |
| iptables / ip rule (percobaan awal) | Runtime | Sudah dihapus saat pindah ke metode `usb0` |
| `tun0` Gnirehtet | Runtime | `gnirehtet stop` |

**Tidak disentuh:** `/system`, `/vendor`, `/product`, boot image, modul Magisk/APatch, sepolicy, `build.prop`, permission file sistem.

### Windows

| Perubahan | Awal → Sekarang | Cara revert |
|---|---|---|
| Service `SharedAccess` | Disabled → Automatic/Running | `restore-default.cmd` |
| ICS sharing `Ethernet` → `Ethernet 2` | Off → On | `restore-default.cmd` |
| Service `WinNat` | Manual → Running | Berhenti sendiri / `Stop-Service WinNat` |
| IP `192.168.137.1` di adapter RNDIS | — | Hilang saat kabel dicabut |
| File proyek di folder kerja | — | Hapus folder |
| Log/screenshot di `%TEMP%\opencode` | — | Hapus manual |

**Tidak berubah:** IP adapter Ethernet utama tetap DHCP `192.168.1.104`, tidak install driver, tidak edit `hosts`.

---

## 8. Ringkasan urutan eksperimen

1. Gnirehtet v2.5.1 (Rust win64) via ADB → VPN jalan, tapi Play Store bermasalah.
2. Coba RNDIS manual: SELinux blok `sys.usb.config` → configfs langsung.
3. `rndis0` muncul, Windows dapat "Remote NDIS Compatible Device" setelah VID/PID diubah ke `05C6:9024`.
4. ICS aktif via VBScript → IP connectivity + HTTPS jalan.
5. DNS gagal karena `net.dns1`/`ndc` tidak berfungsi di Android 17.
6. DNAT port 53 ke ICS DNS → DNS jalan, tapi bergantung data seluler.
7. **Rename `rndis0` → `usb0`** → Android daftarkan Ethernet, DNS otomatis, Play Store jalan tanpa data seluler. ✅

---

## 9. Referensi

- [Gnirehtet — Genymobile](https://github.com/Genymobile/gnirehtet)
- [XDA: Android 14 crippled ndc command](https://xdaforums.com/t/has-android-14-crippled-the-ndc-command.4645821/)
- AOSP: DNS Resolver module — `source.android.com/docs/core/ota/modular-system/dns-resolver`
- `/vendor/etc/init/hw/init.qcom.usb.rc` (perangkat)
