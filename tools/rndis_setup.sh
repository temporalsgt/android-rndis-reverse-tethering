#!/system/bin/sh
# Jalankan di HP sebagai root: su -c sh /data/local/tmp/rndis_setup.sh
# RNDIS -> rename ke usbN agar Android mendaftarkannya sebagai
# jaringan ETHERNET (bukan VPN). DNS otomatis dari DHCP ICS di PC.
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

# tunggu rndis0 benar-benar muncul
i=0
while [ ! -e /sys/class/net/rndis0 ]; do
  i=$((i+1))
  if [ $i -gt 30 ]; then echo "ERROR: rndis0 tidak muncul"; break; fi
  sleep 1
done
echo "rndis0 muncul setelah ${i}s"

# --- rename ke usb0/usb1/... (filter EthernetTracker: (usb|eth)\d+) ---
# usb0 lama yang stale tidak bisa dihapus, jadi cari nama kosong berikutnya.
NEW=""
for n in 0 1 2 3 4 5; do
  if [ ! -e /sys/class/net/usb$n ]; then
    ip link set rndis0 down 2>/dev/null
    if ip link set rndis0 name usb$n 2>/dev/null; then
      NEW=usb$n
      break
    fi
  fi
done
if [ -z "$NEW" ]; then NEW=rndis0; fi
ip link set "$NEW" up 2>/dev/null
echo "antarmuka aktif: $NEW"

# tunggu DHCP dari ICS Windows (192.168.137.1)
sleep 8

setenforce 1
echo "=== selesai $(date) ==="
echo "enforce=$(getenforce)"
echo "link: $(ip -o link show "$NEW" | head -1)"
echo "addr: $(ip -o addr show "$NEW" | grep 'inet ' | head -1)"
echo "dns:  $(dumpsys connectivity 2>/dev/null | grep -m1 'DnsAddresses.*192.168.137.1' >/dev/null && echo 192.168.137.1 || echo CEK_MANUAL)"
