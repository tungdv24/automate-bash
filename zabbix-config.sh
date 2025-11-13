#!/bin/bash

# Exit on any error
set -e

# Function to detect Zabbix Agent version
detect_zabbix_agent() {
    if systemctl status zabbix-agent2 >/dev/null 2>&1; then
        echo "❌ Detected Zabbix Agent 2. This script is only for Zabbix Agent 1."
        exit 1
    elif systemctl status zabbix-agent >/dev/null 2>&1; then
        echo "✅ Detected Zabbix Agent 1. Proceeding..."
    else
        echo "❌ No Zabbix Agent service found. Exiting."
        exit 1
    fi
}

# Run detection
detect_zabbix_agent

# Define temp working directory
TMP_DIR="/tmp/zabbix-configs"
REPO_URL="https://github.com/tungdv24/Ansible.git"

# Define source and target paths
SCRIPTS_SRC="roles/install_zabbix_agent/files/scripts"
SCRIPTS_DST="/etc/zabbix/scripts"

CONF_SRC="roles/install_zabbix_agent/files/zabbix_agentd.d"
CONF_DST="/etc/zabbix/zabbix_agentd.d"

# Ensure destination directories exist
mkdir -p "$SCRIPTS_DST"
mkdir -p "$CONF_DST"

# Remove any old temp clone
rm -rf "$TMP_DIR"

# Clone fresh repo
echo "📥 Cloning repo..."
git clone "$REPO_URL" "$TMP_DIR"

# Copy scripts
echo "📂 Copying scripts to $SCRIPTS_DST..."
cp -a "$TMP_DIR/$SCRIPTS_SRC/." "$SCRIPTS_DST/"

# Copy zabbix_agentd.d configs
echo "📂 Copying agent configs to $CONF_DST..."
cp -a "$TMP_DIR/$CONF_SRC/." "$CONF_DST/"

# Clean up
rm -rf "$TMP_DIR"

# Restart Zabbix Agent
echo "🔁 Restarting Zabbix Agent..."
if systemctl restart zabbix-agent; then
    echo "✅ Zabbix Agent restarted successfully."
else
    echo "❌ Failed to restart Zabbix Agent. Please check the service status."
    systemctl status zabbix-agent
    exit 1
fi
