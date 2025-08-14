#!/bin/bash

# Temporary control socket directory (deleted on exit)
CONTROL_DIR=$(mktemp -d)
PASS_FILE=$(mktemp)

# Cleanup on exit
cleanup() {
    echo -e "\n[INFO] Cleaning up..."
    pkill -f "ssh -S $CONTROL_DIR" 2>/dev/null
    rm -f "$PASS_FILE"
    rm -rf "$CONTROL_DIR"
    echo "[INFO] Closed connections and removed temporary files."
}
trap cleanup EXIT

# Interrupt handler
interrupt() {
    echo -e "\n[INFO] Caught Ctrl+C, stopping immediately..."
    cleanup
    exit 130
}
trap interrupt SIGINT

# Prompt for IPs
clear

if command -v sshpass >/dev/null 2>&1; then
    echo "[INFO] sshpass is already installed. Skipping installation."
else
    # Detect OS and install if missing
    if [ -f /etc/debian_version ]; then
        echo "[INFO] Detected Debian/Ubuntu"
        sudo apt-get update -y
        sudo apt-get install -y sshpass

    elif [ -f /etc/redhat-release ]; then
        echo "[INFO] Detected CentOS/RHEL/Fedora"
        if command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y epel-release
            sudo dnf install -y sshpass
        else
            sudo yum install -y epel-release
            sudo yum install -y sshpass
        fi

    else
        echo "[ERROR] Unsupported OS. Could not install sshpass."
    fi

    echo "[SUCCESS] sshpass installed successfully."
fi


read -p "Enter IP addresses (space-separated): " -a IPS
read -p "Enter SSH port (default 22): " PORT
PORT=${PORT:-22}
read -p "Enter SSH username: " USER
read -s -p "Enter SSH password (leave blank for key auth): " PASS
echo
if [[ -n "$PASS" ]]; then
    echo "$PASS" > "$PASS_FILE"
fi

# Connect to all servers
CONNECTED_SERVERS=()
for IP in "${IPS[@]}"; do
    echo "[INFO] Connecting to $IP..."
    if [[ -s "$PASS_FILE" ]]; then
        sshpass -f "$PASS_FILE" ssh -o StrictHostKeyChecking=no -p "$PORT" \
            -M -S "$CONTROL_DIR/$IP" -fnN "$USER@$IP" && CONNECTED_SERVERS+=("$IP")
    else
        ssh -o StrictHostKeyChecking=no -p "$PORT" \
            -M -S "$CONTROL_DIR/$IP" -fnN "$USER@$IP" && CONNECTED_SERVERS+=("$IP")
    fi
done

# Show connected servers
echo "[INFO] Connected servers:"
for IP in "${CONNECTED_SERVERS[@]}"; do
    echo " - $IP"
done

# Interactive command execution
echo -e "\n[INFO] Enter commands to run on all servers. Press Ctrl+C or Ctrl+D to exit."

while true; do
    echo -n "> "
    if ! IFS= read -r CMD; then
        break
    fi
    [[ -z "$CMD" ]] && continue

    for IP in "${CONNECTED_SERVERS[@]}"; do
        echo -e "\n===== $IP ====="
        ssh -S "$CONTROL_DIR/$IP" "$USER@$IP" "$CMD"
    done
done
