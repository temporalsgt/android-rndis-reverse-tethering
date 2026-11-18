#!/system/bin/sh
# Universal RNDIS reverse-tethering setup (Android, root required).
#
# Tidak ada nilai spesifik perangkat: gadget configfs, UDC, fungsi RNDIS/ADB,
# VID/PID, dan nama antarmuka jaringan semuanya dideteksi saat runtime.
# Jalankan dari HP: su -c sh /data/local/tmp/rndis_setup.sh
#
# Catatan: ADB bisa putus saat UDC di-unbind, jadi script dijalankan background.

LOG=/data/local/tmp/rndis_setup.log
exec >"$LOG" 2>&1
echo "=== mulai $(date) ==="

log() { echo "$*"; }

# ---------------------------------------------------------------------------
# 1. Simpan state SELinux, lalu izinkan sementara configfs diakses shell root.
# ---------------------------------------------------------------------------
SELINUX_BEFORE=$(getenforce 2>/dev/null)
log "selinux_awal=$SELINUX_BEFORE"
setenforce 0 2>/dev/null

# ---------------------------------------------------------------------------
# 2. Deteksi gadget configfs, config node, fungsi RNDIS & ADB, dan UDC.
# ---------------------------------------------------------------------------
G=""
for g in /config/usb_gadget/*; do
    if [ -d "$g/configs" ] && [ -d "$g/functions" ]; then
        G=$g
        break
    fi
done
if [ -z "$G" ]; then
    log "ERROR: /config/usb_gadget/<n> tidak ditemukan. Perangkat harus mendukung USB configfs."
    echo "=== gagal $(date) ==="
    exit 1
fi

B=""
for c in "$G"/configs/*; do
    if [ -d "$c" ]; then
        B=$c
        break
    fi
done
if [ -z "$B" ]; then
    log "ERROR: config node di $G/configs tidak ditemukan."
    echo "=== gagal $(date) ==="
    exit 1
fi

# Fungsi RNDIS: coba nama umum lebih dulu, lalu cari apa pun yang mengandung rndis.
RNDIS_FN=""
for n in gsi.rndis rndis rndis.rndis rndis_bam.rndis f_rndis rndis.gs; do
    if [ -d "$G/functions/$n" ]; then
        RNDIS_FN=$n
        break
    fi
done
if [ -z "$RNDIS_FN" ]; then
    for f in "$G"/functions/*; do
        n=${f##*/}
        case "$n" in
            *rndis*|*RNDIS*) RNDIS_FN=$n; break ;;
        esac
    done
fi

# Fungsi ADB.
ADB_FN=""
for n in ffs.adb adb function_adb ffs.adb.0; do
    if [ -d "$G/functions/$n" ]; then
        ADB_FN=$n
        break
    fi
done
if [ -z "$ADB_FN" ]; then
    for f in "$G"/functions/*; do
        n=${f##*/}
        case "$n" in
            *adb*|*ADB*) ADB_FN=$n; break ;;
        esac
    done
fi

if [ -z "$RNDIS_FN" ] || [ -z "$ADB_FN" ]; then
    log "ERROR: fungsi RNDIS/ADB tidak ditemukan di $G/functions"
    log "rndis=$RNDIS_FN adb=$ADB_FN"
    log "tersedia: $(ls "$G/functions" 2>/dev/null | tr '\n' ' ')"
    echo "=== gagal $(date) ==="
    exit 1
fi

UDC=$(cat "$G/UDC" 2>/dev/null | tr -d '\r\n')
if [ -z "$UDC" ]; then
    UDC=$(ls /sys/class/udc 2>/dev/null | head -1 | tr -d '\r\n')
fi
if [ -z "$UDC" ]; then
    log "ERROR: UDC tidak ditemukan."
    echo "=== gagal $(date) ==="
    exit 1
fi

VID=$(cat "$G/idVendor" 2>/dev/null)
PID=$(cat "$G/idProduct" 2>/dev/null)
VIDPID_SRC="gadget (fallback)"

# VID/PID terbaik diambil dari init-script ROM yang memuat blok rndis.
# Nilai runtime bisa berubah menjadi VID/PID ADB setelah gadget HAL reset,
# jadi jangan selalu dipertahankan.
for rc in /vendor/etc/init/hw/init.*usb*.rc /vendor/etc/init/hw/init.*.rc /vendor/etc/init/*.rc /system/etc/init/*.rc; do
    [ -f "$rc" ] || continue
    # Blok "on" yang memuat rndis + adb, beserta 25 baris isinya.
    block=$(grep -A25 '^on .*rndis.*adb' "$rc" 2>/dev/null)
    if [ -z "$block" ]; then
        block=$(grep -A25 '^on .*rndis' "$rc" 2>/dev/null)
    fi
    v=$(echo "$block" | grep -m1 'idVendor' | grep -o '0x[0-9A-Fa-f][0-9A-Fa-f]*' | head -1)
    p=$(echo "$block" | grep -m1 'idProduct' | grep -o '0x[0-9A-Fa-f][0-9A-Fa-f]*' | head -1)
    if [ -n "$v" ] && [ -n "$p" ]; then
        VID=$v
        PID=$p
        VIDPID_SRC="$rc"
        break
    fi
done

if [ "$VIDPID_SRC" != "gadget (fallback)" ]; then
    echo "$VID" > "$G/idVendor" 2>/dev/null
    echo "$PID" > "$G/idProduct" 2>/dev/null
fi

log "gadget=$G"
log "config=$B"
log "rndis_fn=$RNDIS_FN"
log "adb_fn=$ADB_FN"
log "udc=$UDC"
log "vidpid=$VID:$PID (sumber=$VIDPID_SRC)"

# ---------------------------------------------------------------------------
# 3. Susun ulang gadget: RNDIS + ADB. Symlink lama dihapus semua.
# ---------------------------------------------------------------------------
for l in "$B"/*; do
    [ -L "$l" ] && rm -f "$l"
done

if [ -d "$B/strings/0x409" ]; then
    echo -n "rndis_adb" > "$B/strings/0x409/configuration" 2>/dev/null
fi

if [ -d "$G/os_desc" ]; then
    rm -f "$G/os_desc/b.1" 2>/dev/null
    ln -s "$B" "$G/os_desc/b.1" 2>/dev/null
fi

ln -s "$G/functions/$RNDIS_FN" "$B/f1"
ln -s "$G/functions/$ADB_FN" "$B/f2"

# ---------------------------------------------------------------------------
# 4. Rebind UDC agar gadget aktif. ADB akan putus sejenak di sini.
# ---------------------------------------------------------------------------
echo "" > "$G/UDC" 2>/dev/null
sleep 2
echo "$UDC" > "$G/UDC" 2>/dev/null
log "udc direbind"

# ---------------------------------------------------------------------------
# 5. Tunggu antarmuka jaringan gadget muncul (rndis*/usb*/eth*).
# ---------------------------------------------------------------------------
wait_interface() {
    i=0
    while [ "$i" -lt 40 ]; do
        for d in /sys/class/net/*; do
            n=${d##*/}
            case "$n" in
                lo|dummy*|rmnet*|wwan*|wlan*|sit*|ip6tnl*|tun*|bnep*|bt-pan*|veth*|bridge*) continue ;;
            esac
            case "$n" in
                rndis*|usb*|eth*)
                    echo "$n"
                    return 0
                    ;;
            esac
        done
        sleep 1
        i=$((i + 1))
    done
    return 1
}

IF=$(wait_interface)
if [ -z "$IF" ]; then
    log "ERROR: antarmuka RNDIS tidak muncul dalam 40 detik."
    echo "=== gagal $(date) ==="
    exit 1
fi
log "antarmuka_awal=$IF"

# Biarkan antarmuka DOWN sampai setelah di-rename. IpClient Android harus
# dimulai pada nama akhir, bukan pada nama gadget sementara (rndisN).
ip link set "$IF" down 2>/dev/null

is_ethernet() {
    dumpsys connectivity 2>/dev/null | grep "InterfaceName: $IF" | grep -q "Transports: ETHERNET"
}

# ---------------------------------------------------------------------------
# 6. Rename ke usbN/ethN agar lolos filter EthernetTracker ROM
#    (umumnya (usb|eth)\d+). Nama kosong pertama dipilih.
# ---------------------------------------------------------------------------
# usb0 sengaja didahulukan terakhir: pada sebagian ROM nama itu dipakai
# Android sebagai "interface used for tethering", sehingga DHCP client tidak jalan.
for prefix in usb eth; do
    for n in 1 2 3 4 5 6 7 0; do
        CAND=${prefix}${n}
        if [ -e "/sys/class/net/$CAND" ]; then
            continue
        fi
        if ip link set "$IF" name "$CAND" 2>/dev/null; then
            IF=$CAND
            log "di-rename ke $IF"
            break 2
        fi
    done
done
ip link set "$IF" up 2>/dev/null
sleep 2

# ---------------------------------------------------------------------------
# 7. Tunggu DHCP dari ICS Windows (bukan sleep tetap).
# ---------------------------------------------------------------------------
ADDR=""
i=0
while [ "$i" -lt 30 ]; do
    LINE=$(ip -o addr show dev "$IF" 2>/dev/null | grep -m1 'inet ')
    if [ -n "$LINE" ]; then
        set -- $LINE
        ADDR=$4
        break
    fi
    sleep 1
    i=$((i + 1))
done

DNS=$(dumpsys connectivity 2>/dev/null | grep -m1 "InterfaceName: $IF" | grep -o 'DnsAddresses: \[[^]]*\]')

# ---------------------------------------------------------------------------
# 8. Pulihkan SELinux dan lapor hasil.
# ---------------------------------------------------------------------------
case "$SELINUX_BEFORE" in
    Enforcing)  setenforce 1 2>/dev/null ;;
    Permissive) setenforce 0 2>/dev/null ;;
esac

log "antarmuka=$IF"
log "addr=$ADDR"
log "dns=$DNS"
log "ethernet=$(if is_ethernet; then echo yes; else echo no; fi)"
log "selinux_akhir=$(getenforce 2>/dev/null)"
echo "=== selesai $(date) ==="
exit 0
