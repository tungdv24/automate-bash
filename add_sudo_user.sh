#!/bin/bash
set -euo pipefail

# ==============================================================================
# Script: add_sudo_user.sh
# Purpose: Create or update a sudo user, safely append SSH public key,
#          configure passwordless sudo, and update sshd AllowUsers safely.
# ==============================================================================

# Ensure root privileges
if [[ $EUID -ne 0 ]]; then
    echo "❌ Error: This script must be run as root or with sudo."
    exit 1
fi

USERNAME=""
PUBKEY=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user|-u)
            USERNAME="$2"
            shift 2
            ;;
        --key|-k)
            PUBKEY="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: sudo $0 --user <username> --key <ssh_public_key>"
            echo ""
            echo "Options:"
            echo "  -u, --user <username>  Target username"
            echo "  -k, --key  <pubkey>    SSH public key string"
            echo "  -h, --help             Show this help message"
            exit 0
            ;;
        *)
            echo "❌ Unknown argument: $1"
            echo "Usage: sudo $0 --user <username> --key <ssh_public_key>"
            exit 1
            ;;
    esac
done

# Validate inputs
if [[ -z "$USERNAME" || -z "$PUBKEY" ]]; then
    echo "❌ Error: Both --user and --key arguments are required."
    echo "Usage: sudo $0 --user <username> --key <ssh_public_key>"
    exit 1
fi

echo "=========================================================="
echo "          Add / Update Sudo User with SSH Key             "
echo "=========================================================="
echo "Username : $USERNAME"
echo "=========================================================="

# 1. Create user if not exists
echo ">>> [1/5] Checking user existence..."
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -s /bin/bash "$USERNAME"
    echo "✅ Created new user: $USERNAME"
else
    echo "ℹ️  User '$USERNAME' already exists."
fi

# Detect home directory safely
USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
    USER_HOME=$(eval echo "~$USERNAME")
fi

# 2. Append SSH public key safely (without overwriting)
echo ">>> [2/5] Configuring SSH authorized_keys..."
mkdir -p "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"
AUTH_KEYS="$USER_HOME/.ssh/authorized_keys"
touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"

if grep -qxF "$PUBKEY" "$AUTH_KEYS" 2>/dev/null; then
    echo "ℹ️  SSH key is already present in $AUTH_KEYS (skipped)."
else
    # Ensure newline before appending if file is not empty
    if [[ -s "$AUTH_KEYS" && -n "$(tail -c 1 "$AUTH_KEYS")" ]]; then
        echo "" >> "$AUTH_KEYS"
    fi
    echo "$PUBKEY" >> "$AUTH_KEYS"
    echo "✅ SSH key successfully appended to $AUTH_KEYS"
fi
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"

# 3. Add to sudo/wheel group
echo ">>> [3/5] Assigning sudo privileges..."
if getent group sudo &>/dev/null; then
    usermod -aG sudo "$USERNAME"
    echo "✅ Added '$USERNAME' to group 'sudo'"
elif getent group wheel &>/dev/null; then
    usermod -aG wheel "$USERNAME"
    echo "✅ Added '$USERNAME' to group 'wheel'"
else
    echo "⚠️  No default sudo group (sudo or wheel) found."
fi

# Configure sudoers file
SUDOERS_FILE="/etc/sudoers.d/$USERNAME"
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"

if command -v visudo &>/dev/null; then
    if ! visudo -cf "$SUDOERS_FILE" &>/dev/null; then
        echo "❌ visudo validation failed on $SUDOERS_FILE! Removing file for safety."
        rm -f "$SUDOERS_FILE"
        exit 1
    fi
fi
echo "✅ Passwordless sudo configured at $SUDOERS_FILE"

# 4. Handle AllowUsers in /etc/ssh/sshd_config safely
echo ">>> [4/5] Checking sshd AllowUsers setting..."
if [ -f /etc/ssh/sshd_config ] && grep -E "^[[:space:]]*AllowUsers" /etc/ssh/sshd_config &>/dev/null; then
    if grep -E "^[[:space:]]*AllowUsers" /etc/ssh/sshd_config | grep -qw "$USERNAME"; then
        echo "ℹ️  User '$USERNAME' already present in AllowUsers."
    else
        # Append username to the end of the first AllowUsers line
        sed -i -E "0,/^[[:space:]]*AllowUsers.*/s/^([[:space:]]*AllowUsers.*)/\1 $USERNAME/" /etc/ssh/sshd_config
        echo "✅ Appended '$USERNAME' to existing AllowUsers line in /etc/ssh/sshd_config"
    fi
else
    echo "ℹ️  No AllowUsers restriction found in /etc/ssh/sshd_config (skipping)."
fi

# 5. Verify sshd configuration and restart SSH service safely
echo ">>> [5/5] Testing and restarting SSH service..."
if command -v sshd &>/dev/null; then
    if ! sshd -t; then
        echo "❌ Error: 'sshd -t' check failed! SSH service was NOT restarted to prevent lockout."
        exit 1
    fi
fi

if systemctl is-active sshd &>/dev/null; then
    systemctl reload-or-restart sshd 2>/dev/null || systemctl restart sshd
elif systemctl is-active ssh &>/dev/null; then
    systemctl reload-or-restart ssh 2>/dev/null || systemctl restart ssh
elif command -v service &>/dev/null; then
    service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || true
fi

echo "=========================================================="
echo "🎉 User '$USERNAME' configured with sudo & SSH key successfully!"
echo "=========================================================="
