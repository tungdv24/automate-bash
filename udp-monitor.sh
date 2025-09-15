#!/bin/bash
set -e

### 1. Create nftables table + chains + counters
echo "[*] Setting up nftables rules..."
sudo nft add table inet dnsmon 2>/dev/null || true
sudo nft add chain inet dnsmon input  '{ type filter hook input priority 0 ; }' 2>/dev/null || true
sudo nft add chain inet dnsmon output '{ type filter hook output priority 0 ; }' 2>/dev/null || true

# Add counters (if not already exist)
sudo nft add rule inet dnsmon input  udp dport 53 counter name dns_in 2>/dev/null || true
sudo nft add rule inet dnsmon output udp sport 53 counter name dns_out 2>/dev/null || true

### 2. Add UserParameters into Zabbix config
ZBX_CONF="/etc/zabbix/zabbix_agentd.d/dns.conf"

echo "[*] Writing Zabbix UserParameters to $ZBX_CONF ..."
sudo tee "$ZBX_CONF" > /dev/null <<'EOF'
UserParameter=port.53.conn.in,ss -uant | awk '$5 ~ /:53$/ {print}' | wc -l

# DNS incoming traffic (packets)
UserParameter=port.53.packets.in,sudo nft list counter inet dnsmon dns_in | awk '/packets/ {print $2}'

# DNS outgoing traffic (packets)
UserParameter=port.53.packets.out,sudo nft list counter inet dnsmon dns_out | awk '/packets/ {print $2}'

# DNS incoming traffic (bytes)
UserParameter=port.53.bytes.in,sudo nft list counter inet dnsmon dns_in | awk '/bytes/ {print $4}'

# DNS outgoing traffic (bytes)
UserParameter=port.53.bytes.out,sudo nft list counter inet dnsmon dns_out | awk '/bytes/ {print $4}'
EOF

### 3. Allow Zabbix to run nft via sudo without password
echo "[*] Adding sudoers entry for Zabbix..."
SUDOERS_FILE="/etc/sudoers.d/zabbix-iptables"
sudo tee "$SUDOERS_FILE" > /dev/null <<'EOF'
zabbix ALL=(ALL) NOPASSWD: /usr/sbin/nft list *
EOF
sudo chmod 440 "$SUDOERS_FILE"

### 4. Restart Zabbix agent
echo "[*] Restarting Zabbix agent..."
if command -v systemctl >/dev/null; then
    sudo systemctl restart zabbix-agent
else
    sudo service zabbix-agent restart
fi

echo "[*] Done! Now you can test with:"
echo "    zabbix_get -s <server_ip> -k port.53.bytes.in"

