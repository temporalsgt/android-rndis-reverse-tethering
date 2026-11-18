#!/system/bin/sh
# Jalankan di HP sebagai root: su -c sh /data/local/tmp/rndis_setup.sh
# RNDIS -> rename jadi usb0 agar Android mendaftarkannya sebagai
# jaringan ETHERNET (bukan VPN), DNS otomatis dari DHCP ICS di PC.
G=/config/usb_gadget/g1
B=$G/configs/b.1
LOG=/data/local/tmp/rndis_setup.log
exec >$LOG 2>&1
echo "=== mulai $(date) ==="

setenforce 0

# --- gadget USB: RNDIS + ADB ---
for f in f1 f2 f3 f4 f5 f6 f7 f8 f9 function0 function1; do
  rm -f "$B/$f"
done
echo -n "rndis_adb" > "$B/strings/0x409/configuration"
rm -f "$G/os_desc/b.1"
ln -s "$B" "$G/os_desc/b.1"
echo 0x05C6 > "$G/idVendor"
echo 0x9024 > "$G/idProduct"
ln -s "$G/functions/gsi.rndis" "$B/f1"
ln -s "$G/functions/ffs.adb" "$B/f2"

# --- rebind UDC (ADB bisa putus sejenak) ---
echo "" > "$G/UDC"
sleep 3
echo <udc> > "$G/UDC"
sleep 6

# --- rename rndis0 -> usb0 agar terdeteksi EthernetTracker ---
# filter HP ini: (usb|eth)\d+
ip link set rndis0 down 2>/dev/null
ip link set rndis0 name usb0 2>/dev/null
echo "rename RC=$?"
ip link set usb0 up 2>/dev/null

# tunggu DHCP dari ICS Windows (192.168.137.1)
sleep 8

setenforce 1
echo "=== selesai $(date) ==="
echo "enforce=$(getenforce)"
echo "link: $(ip -o link show usb0 2>&1 | head -1)"
echo "addr: $(ip -o addr show usb0 2>&1 | grep 'inet ' | head -1)"
echo "dns:  $(dumpsys connectivity 2>/dev/null | grep -m1 'DnsAddresses.*192.168.137.1' >/dev/null && echo 192.168.137.1 || echo CEK_MANUAL)"
