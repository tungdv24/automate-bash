#!/bin/bash

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

# Temporary password file
PASS_FILE="$(mktemp)"
trap 'rm -f "$PASS_FILE"; echo -e "\nCtrl+C received — exiting."; exit 130' INT TERM

# Prompt for IPs
echo "Enter IP addresses (space-separated):"
read -r IPS

# Prompt for SSH port (default 22)
read -p "Enter SSH port [default 22]: " PORT
PORT=${PORT:-22}

# Prompt for username
read -p "Enter SSH username: " USERNAME

# Prompt for password (optional, press enter to skip for key auth)
read -s -p "Enter SSH password (leave blank for key auth): " PASSWORD
echo
if [[ -n "$PASSWORD" ]]; then
    echo "$PASSWORD" > "$PASS_FILE"
fi

# Convert IP string to array
IP_ARRAY=($IPS)
TOTAL=${#IP_ARRAY[@]}

# Iterate over each IP and open interactive SSH
for i in "${!IP_ARRAY[@]}"; do
    IP="${IP_ARRAY[$i]}"
    echo "--------------------------------"
    echo "($((i+1))/$TOTAL) Connecting to $IP ..."
    echo "--------------------------------"

    if [[ -s "$PASS_FILE" ]]; then
        sshpass -f "$PASS_FILE" ssh -p "$PORT" -o StrictHostKeyChecking=no "$USERNAME@$IP"
    else
        ssh -p "$PORT" -o StrictHostKeyChecking=no "$USERNAME@$IP"
    fi
done

echo "All connections completed."
