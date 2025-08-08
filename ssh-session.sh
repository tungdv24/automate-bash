#!/bin/bash

clear

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
