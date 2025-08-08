#!/bin/bash

# Temporary control socket directory (deleted on exit)
CONTROL_DIR=$(mktemp -d)

# Temp password file
PASS_FILE=$(mktemp)

# Cleanup on exit
cleanup() {
    rm -f "$PASS_FILE"
    rm -rf "$CONTROL_DIR"
    echo -e "\n[INFO] Cleaned up temporary files and closed connections."
}
trap cleanup EXIT INT

# Prompt for IPs

clear

read -p "Enter IP addresses (space-separated): " -a IPS

# Prompt for SSH port (default 22)
read -p "Enter SSH port (default 22): " PORT
PORT=${PORT:-22}

# Prompt for username
read -p "Enter SSH username: " USER

# Prompt for password (optional for key auth)
read -s -p "Enter SSH password (leave blank for key auth): " PASS
echo
if [[ -n "$PASS" ]]; then
    echo "$PASS" > "$PASS_FILE"
fi

# Connect to all servers and open control sockets
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
echo -e "\n[INFO] Enter commands to run on all servers. Press Ctrl+D to exit."
while true; do
    echo -n "> "
    if ! IFS= read -r CMD; then
        break  # Exit on Ctrl+D
    fi

    # If empty command, skip instead of breaking
    if [[ -z "$CMD" ]]; then
        continue
    fi

    for IP in "${CONNECTED_SERVERS[@]}"; do
        echo -e "\n===== $IP ====="
        ssh -S "$CONTROL_DIR/$IP" "$USER@$IP" "$CMD"
    done
done