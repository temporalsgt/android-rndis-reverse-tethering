#!/system/bin/sh
# reset_usb_termux.sh — kembalikan gadget USB ke mode ADB normal.
# Jalankan di HP lewat Termux. Membutuhkan root (su).
#
# Pakai saat:
#   - HP hilang dari adb devices setelah sesi RNDIS
#   - gadget stuck di rndis_adb / USB tidak ter-enumerasi
#
# Setelah script ini, CABUT-PASANG kabel USB (atau reboot HP).

echo ""
echo "=========================================="
echo " RESET USB -> MODE ADB (dari Termux)"
echo "=========================================="

if ! command -v su >/dev/null 2>&1; then
    echo "ERROR: su tidak ditemukan. Butuh root."
    exit 1
fi
if ! su -c id 2>/dev/null | grep -q 'uid=0'; then
    echo "ERROR: akses root belum diberikan ke Termux."
    exit 1
fi

echo "[1/4] Mode SELinux sementara permissive..."
su -c 'setenforce 0' 2>/dev/null

echo "[2/4] Set konfigurasi USB ke adb..."
su -c 'setprop persist.sys.usb.config adb' 2>/dev/null
su -c 'setprop sys.usb.config adb' 2>/dev/null

echo "[3/4] Reset gadget USB..."
su -c 'svc usb resetUsbGadget' 2>/dev/null
sleep 2

echo "[4/4] Kembalikan SELinux..."
su -c 'setenforce 1' 2>/dev/null

echo ""
echo "Selesai. Nilai sekarang:"
echo "  persist.sys.usb.config = $(getprop persist.sys.usb.config)"
echo "  sys.usb.config         = $(getprop sys.usb.config)"
echo ""
echo ">>> CABUT lalu PASANG KABEL USB, atau reboot HP."
echo ">>> Setelah itu cek dari PC: adb devices"
echo ""
