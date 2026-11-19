#!/system/bin/sh
# usb_reset_gadget.sh — kembalikan gadget USB dari komposisi RNDIS
# ke konfigurasi sebelum sesi tethering. Dijalankan root oleh
# restore-default.cmd lewat ADB.
#
# Tidak ada hardcode gadget/config/UDC: semuanya dideteksi saat runtime.

LOG=/data/local/tmp/rndis_setup.log
log() { echo "$*"; }

SELINUX_BEFORE=$(getenforce 2>/dev/null)
setenforce 0 2>/dev/null

# ---------------------------------------------------------------- gadget
G=""
for g in /config/usb_gadget/*; do
    if [ -d "$g/configs" ] && [ -d "$g/functions" ]; then
        G=$g
        break
    fi
done
if [ -z "$G" ]; then
    log "reset: gadget configfs tidak ditemukan"
    exit 1
fi

# Cari config node yang masih punya symlink fungsi RNDIS.
B=""
for c in "$G"/configs/*; do
    [ -d "$c" ] || continue
    for l in "$c"/*; do
        [ -L "$l" ] || continue
        case "$(readlink "$l" 2>/dev/null)" in
            *rndis*|*RNDIS*) B=$c; break 2 ;;
        esac
    done
done

# Fallback: config node pertama (untuk kondisi sudah sebagian dibersihkan).
if [ -z "$B" ]; then
    for c in "$G"/configs/*; do
        [ -d "$c" ] && B=$c && break
    done
fi
if [ -z "$B" ]; then
    log "reset: config node tidak ditemukan"
    exit 1
fi

UDC=$(cat "$G/UDC" 2>/dev/null | tr -d '\r\n')

# Nilai konfigurasi awal: diambil dari log yang ditulis rndis_setup.sh.
# Fallback ke persist prop, lalu ke "adb".
ORIG=""
if [ -f "$LOG" ]; then
    ORIG=$(grep -m1 '^konfigurasi_awal=' "$LOG" 2>/dev/null | cut -d= -f2-)
fi
[ -n "$ORIG" ] || ORIG=$(getprop persist.sys.usb.config 2>/dev/null)
[ -n "$ORIG" ] || ORIG=adb

log "reset: gadget=$G config=$B udc=$UDC konfigurasi=$ORIG"

# ---------------------------------------------------------------- hapus RNDIS
# Symlink ADB sengaja dipertahankan agar koneksi ADB tidak hilang.
for l in "$B"/*; do
    [ -L "$l" ] || continue
    case "$(readlink "$l" 2>/dev/null)" in
        *rndis*|*RNDIS*)
            rm -f "$l"
            log "reset: hapus symlink $l"
            ;;
    esac
done

echo -n "$ORIG" > "$B/strings/0x409/configuration" 2>/dev/null

# Kembalikan os_desc ke config node yang sama (setup membuat symlink ini).
if [ -d "$G/os_desc" ]; then
    rm -f "$G/os_desc/b.1" 2>/dev/null
    ln -s "$B" "$G/os_desc/b.1" 2>/dev/null
fi

# ---------------------------------------------------------------- rebind UDC
if [ -n "$UDC" ]; then
    echo "" > "$G/UDC" 2>/dev/null
    sleep 2
    echo "$UDC" > "$G/UDC" 2>/dev/null
    log "reset: UDC direbind"
else
    log "reset: UDC kosong, rebind dilewati (cabut-pasang kabel akan melakukan ini)"
fi

# ---------------------------------------------------------------- SELinux
case "$SELINUX_BEFORE" in
    Enforcing)  setenforce 1 2>/dev/null ;;
    Permissive) setenforce 0 2>/dev/null ;;
esac

log "reset: selesai"
exit 0
