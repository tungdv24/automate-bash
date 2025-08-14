#!/bin/bash
set -e

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            USERNAME="$2"
            shift 2
            ;;
        --key)
            PUBKEY="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 --user <username> --key <ssh_public_key>"
            exit 1
            ;;
    esac
done

# Validate inputs
if [[ -z "$USERNAME" || -z "$PUBKEY" ]]; then
    echo "Error: Both --user and --key arguments are required."
    echo "Usage: $0 --user <username> --key <ssh_public_key>"
    exit 1
fi

echo "[*] Creating user: $USERNAME"
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -s /bin/bash "$USERNAME"
else
    echo "[*] User already exists"
fi

echo "[*] Adding SSH key"
USER_HOME=$(eval echo "~$USERNAME")
mkdir -p "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"
echo "$PUBKEY" > "$USER_HOME/.ssh/authorized_keys"
chmod 600 "$USER_HOME/.ssh/authorized_keys"
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"

# Detect and add to the correct sudo group
if getent group sudo &>/dev/null; then
    echo "[*] Adding user to sudo group"
    usermod -aG sudo "$USERNAME"
elif getent group wheel &>/dev/null; then
    echo "[*] Adding user to wheel group"
    usermod -aG wheel "$USERNAME"
else
    echo "[!] No known sudo-capable group (sudo or wheel) found."
fi

echo "[*] Configuring passwordless sudo"
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
chmod 440 "/etc/sudoers.d/$USERNAME"

echo "[*] Checking sshd_config AllowUsers setting..."

# Get all AllowUsers entries (if any)
ALLOW_LINES=$(grep -E "^AllowUsers" /etc/ssh/sshd_config || true)

if [[ -n "$ALLOW_LINES" ]]; then
    # Extract all users from all AllowUsers lines
    CURRENT_USERS=$(echo "$ALLOW_LINES" | awk '{$1=""; print $0}' | tr -s ' ' | tr '\n' ' ' | sed 's/^ //;s/ $//')

    echo "[*] Currently allowed users: $CURRENT_USERS"

    # Check if our user is already in the list
    if echo "$CURRENT_USERS" | grep -qw "$USERNAME"; then
        echo "[*] $USERNAME already present in AllowUsers"
    else
        # Append user to the LAST AllowUsers line
        sed -i "\$aAllowUsers $USERNAME" /etc/ssh/sshd_config
        echo "[*] Added $USERNAME to AllowUsers"
    fi
else
    echo "[*] No AllowUsers restriction found — skipping changes"
fi


echo "[*] Restarting SSH service"
if systemctl is-active sshd &>/dev/null; then
    systemctl restart sshd
elif systemctl is-active ssh &>/dev/null; then
    systemctl restart ssh
else
    service ssh restart
fi

echo "[✓] User $USERNAME created and configured successfully!"
