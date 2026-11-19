#!/system/bin/sh
# usb_status_termux.sh — cek kondisi USB dari dalam HP (jalankan lewat Termux).
#
# Cara pakai:
#   bash tools/usb_status_termux.sh
#   sh tools/usb_status_termux.sh
#
# Read-only: tidak mengubah konfigurasi apa pun.
# Root (su) hanya dipakai untuk membaca configfs & log; kalau tidak ada,
# bagian itu akan ditandai tidak tersedia.

echo ""
echo "=========================================="
echo " USB STATUS - sisi Android (Termux)"
echo "=========================================="

# ---------------------------------------------------------------- helper
ROOT=0
if command -v su >/dev/null 2>&1; then
    if su -c id 2>/dev/null | grep -q 'uid=0'; then
        ROOT=1
    fi
fi

run_root() {
    if [ "$ROOT" -eq 1 ]; then
        su -c "$1" 2>/dev/null
    else
        sh -c "$1" 2>/dev/null
    fi
}

section() { echo ""; echo "=== $1 ==="; }

# ---------------------------------------------------------------- identitas
section "PERANGKAT"
echo "serial   : $(getprop ro.serialno 2>/dev/null)"
echo "model    : $(getprop ro.product.model 2>/dev/null)"
echo "android  : $(getprop ro.build.version.release 2>/dev/null)"
if [ "$ROOT" -eq 1 ]; then
    echo "root     : tersedia (su)"
else
    echo "root     : TIDAK tersedia — configfs/log mungkin tidak terbaca"
fi

# ---------------------------------------------------------------- props USB
section "KONFIGURASI USB"
PERSIST=$(getprop persist.sys.usb.config 2>/dev/null)
CURRENT=$(getprop sys.usb.config 2>/dev/null)
USTATE=$(getprop sys.usb.state 2>/dev/null)
FUNCS=$(svc usb getFunctions 2>/dev/null)
echo "persist.sys.usb.config : $PERSIST"
echo "sys.usb.config         : $CURRENT"
echo "sys.usb.state          : $USTATE"
echo "fungsi aktif           : $FUNCS"

# ---------------------------------------------------------------- configfs
section "CONFIGFS GADGET"
G=""
for g in /config/usb_gadget/*; do
    if [ -d "$g/configs" ] && [ -d "$g/functions" ]; then
        G=$g
        break
    fi
done
UDC=""; CFG=""; VID=""; PID=""
if [ -n "$G" ]; then
    UDC=$(run_root "cat $G/UDC 2>/dev/null")
    VID=$(run_root "cat $G/idVendor 2>/dev/null")
    PID=$(run_root "cat $G/idProduct 2>/dev/null")
    for c in "$G"/configs/*; do
        [ -d "$c" ] || continue
        CFG=$(run_root "cat $c/strings/0x409/configuration 2>/dev/null")
        [ -n "$CFG" ] && break
    done
    echo "gadget   : $G"
    echo "UDC      : ${UDC:-(tidak terbaca)}"
    echo "config   : ${CFG:-(tidak terbaca)}"
    echo "VID:PID  : ${VID:-?}:${PID:-?}"
else
    echo "configfs tidak ditemukan di /config/usb_gadget/"
fi

# ---------------------------------------------------------------- antarmuka
section "ANTARMUKA JARINGAN"
IF=""
for d in /sys/class/net/*; do
    n=${d##*/}
    case "$n" in
        usb*|eth*|rndis*)
            IF=$n
            echo "antarmuka: $n"
            ;;
    esac
done
if [ -z "$IF" ]; then
    echo "antarmuka usb/eth/rndis: TIDAK ADA"
fi

ADDR=""
if [ -n "$IF" ]; then
    LINE=$(ip -o addr show dev "$IF" 2>/dev/null | grep -m1 'inet ')
    if [ -n "$LINE" ]; then
        set -- $LINE
        ADDR=$4
        echo "alamat IP: $ADDR"
    else
        echo "alamat IP: TIDAK ADA"
    fi
fi

# ---------------------------------------------------------------- ethernet framework
section "ETHERNET FRAMEWORK"
FILTER=$(dumpsys ethernet 2>/dev/null | grep -m1 'interface name filter')
TRACKED=$(dumpsys ethernet 2>/dev/null | grep -E '(usb|eth)[0-9]+:' | head -5)
echo "filter   : ${FILTER:-(tidak terbaca)}"
if [ -n "$TRACKED" ]; then
    echo "terlacak :"
    echo "$TRACKED"
else
    echo "terlacak : TIDAK ADA"
fi

if [ -n "$IF" ]; then
    DNS=$(dumpsys connectivity 2>/dev/null | grep -m1 "InterfaceName: $IF" | grep -o 'DnsAddresses: \[[^]]*\]')
    if [ -n "$DNS" ]; then
        echo "DNS      : $DNS"
    fi
fi

# ---------------------------------------------------------------- log sesi terakhir
section "LOG SESI TERAKHIR"
LOG=/data/local/tmp/rndis_setup.log
LOGLINE=$(run_root "grep -E '^(antarmuka|addr|dns|ethernet)=' $LOG")
if [ -n "$LOGLINE" ]; then
    echo "$LOGLINE"
else
    echo "log tidak ada / tidak bisa dibaca"
fi

# ---------------------------------------------------------------- kesimpulan
section "KESIMPULAN"
HAS_IP=0
HAS_RNDIS_CFG=0
case "$ADDR" in
    192.168.137.*) HAS_IP=1 ;;
esac
case "$CFG" in
    *rndis*|*RNDIS*) HAS_RNDIS_CFG=1 ;;
esac
case "$CURRENT$PERSIST" in
    *rndis*) HAS_RNDIS_CFG=1 ;;
esac

if [ "$HAS_IP" -eq 1 ] && [ -n "$TRACKED" ]; then
    echo "MODE RNDIS / reverse tethering SEDANG AKTIF."
    echo "HP sudah dapat IP dari ICS dan terdaftar sebagai Ethernet."
elif [ "$HAS_RNDIS_CFG" -eq 1 ] || [ "$HAS_IP" -eq 1 ]; then
    echo "KONDISI TRANSISI: ada jejak RNDIS tapi belum aktif penuh."
    echo "Cek alamat IP / Ethernet di atas, atau jalankan ulang rndis-tethering.cmd."
else
    echo "MODE NORMAL (ADB/MTP) - belum masuk RNDIS."
    if [ -n "$PERSIST" ] && [ "$PERSIST" != "adb" ]; then
        echo "Catatan: persist.sys.usb.config = '$PERSIST' (bawaan: 'adb')."
    fi
fi

echo ""
