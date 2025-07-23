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

echo "[*] Adding user to sudo group"
usermod -aG sudo "$USERNAME"

echo "[*] Configuring passwordless sudo"
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
chmod 440 "/etc/sudoers.d/$USERNAME"

echo "[*] Configuring sshd_config AllowUsers"
if ! grep -qE "^AllowUsers" /etc/ssh/sshd_config; then
    echo "AllowUsers $USERNAME" >> /etc/ssh/sshd_config
    echo "[*] Added AllowUsers line"
else
    if ! grep -qE "AllowUsers.*\b$USERNAME\b" /etc/ssh/sshd_config; then
        sed -i "/^AllowUsers/ s/$/ $USERNAME/" /etc/ssh/sshd_config
        echo "[*] Appended $USERNAME to AllowUsers"
    else
        echo "[*] $USERNAME already present in AllowUsers"
    fi
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

