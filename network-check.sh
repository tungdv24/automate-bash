#!/bin/bash

# ===== Get Current Public IP =====
CURRENT_IP=$(curl -s ifconfig.me || curl -s icanhazip.com)
echo "CurrentIP (Public): $CURRENT_IP"
echo "======================================"

# ===== DNS Check =====
echo "DNS Check:"
dns_servers=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}')
echo "Configured DNS Servers:"
echo "$dns_servers" | sed 's/^/    /'

# Test DNS resolution speed & IPs
dns_test=$(dig +stats google.com @$(echo "$dns_servers" | head -n1) 2>/dev/null)
resolved_ips=$(echo "$dns_test" | awk '/^google.com/ {print $5}')
query_time=$(echo "$dns_test" | grep "Query time" | awk '{print $4}')

if [[ -n "$resolved_ips" ]]; then
    echo "Resolved google.com to: $resolved_ips"
    echo "Query Time: ${query_time} ms"
else
    echo "❌ DNS resolution failed!"
fi

echo "======================================"

# ===== IP List (Format: "IP - Location") =====
IP_LIST=(
    "8.8.8.8 - Google"
    "103.53.170.12 - FPT-103"
    "42.113.207.88 - FPT-42"
    "119.82.133.100 - CMC-TanThuan"
    "42.96.62.252 - CMC-SG"
    "103.138.114.124 - Viettel"
)

# ===== Loop Through IP List =====
for entry in "${IP_LIST[@]}"; do
    ip=$(echo "$entry" | awk -F' - ' '{print $1}')
    location=$(echo "$entry" | awk -F' - ' '{print $2}')

    echo "Connecting to $ip - $location..."

    # Flood ping with 100 packets (requires root)
    ping_result=$(ping -c 100 -f "$ip" 2>/dev/null)

    # Extract packet loss and average latency
    packet_loss=$(echo "$ping_result" | grep -oP '\d+(?=% packet loss)')
    avg_time=$(echo "$ping_result" | grep -oP '(?<=/)\d+\.\d+(?=/)' | tail -n 1)

    echo "Result:Packet Loss=${packet_loss}%, Avg=${avg_time} ms"

    # Traceroute
    echo "Traceroute to $ip:"
    traceroute -n "$ip" | sed 's/^/    /'

    echo "--------------------------------------"
done
