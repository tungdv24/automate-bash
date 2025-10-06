#!/bin/bash

# === Check input ===
if [[ $# -lt 2 ]]; then
    echo "Usage: bash ssh-login-telegram.sh <TELEGRAM_BOT_TOKEN> <CHAT_ID> [THREAD_ID]"
    exit 1
fi

BOT_TOKEN="$1"
CHAT_ID="$2"
THREAD_ID="$3"

SCRIPT_URL="https://raw.githubusercontent.com/tungdv24/automate-bash/main/ssh-login.sh"
DEST_DIR="/usr/local/sbin"
DEST_SCRIPT="$DEST_DIR/ssh-login.sh"

# === Detect SELinux on CentOS/RHEL and abort if not disabled ===
if [[ -f /etc/centos-release || -f /etc/redhat-release ]]; then
    SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Disabled")
    CONFIG_FILE="/etc/selinux/config"

    if [[ "$SELINUX_STATUS" != "Disabled" ]]; then
        echo "❌ SELinux is currently set to: $SELINUX_STATUS"
        echo "   ➤ Please disable SELinux before running this script."
        echo "   ➤ You can do this by editing $CONFIG_FILE and setting:"
        echo "         SELINUX=disabled"
        echo "   ➤ Then reboot the system."
        exit 3
    fi

    if grep -q '^SELINUX=' "$CONFIG_FILE"; then
        CONFIG_VALUE=$(grep '^SELINUX=' "$CONFIG_FILE" | cut -d= -f2)
        if [[ "$CONFIG_VALUE" != "disabled" ]]; then
            echo "❌ SELinux config is set to: $CONFIG_VALUE"
            echo "   ➤ Please update $CONFIG_FILE to set SELINUX=disabled and reboot."
            exit 4
        fi
    fi
fi

# === Create destination directory if it doesn't exist ===
if [[ ! -d "$DEST_DIR" ]]; then
    mkdir -p "$DEST_DIR"
    echo "✅ Created directory: $DEST_DIR"
fi

# === Download script and configure it ===
curl -fsSL "$SCRIPT_URL" -o "$DEST_SCRIPT"
if [[ $? -ne 0 ]]; then
    echo "❌ Failed to download script from $SCRIPT_URL"
    exit 2
fi

# === Replace placeholders ===
sed -i "s|^telegrambot=.*|telegrambot=\"$BOT_TOKEN\"|" "$DEST_SCRIPT"
sed -i "s|^telegramchatid=.*|telegramchatid=\"$CHAT_ID\"|" "$DEST_SCRIPT"

if [[ -n "$THREAD_ID" ]]; then
    sed -i "s|^thread_id=.*|thread_id=\"$THREAD_ID\"|" "$DEST_SCRIPT"
else
    sed -i "s|^thread_id=.*|thread_id=\"\"|" "$DEST_SCRIPT"
fi

chmod +x "$DEST_SCRIPT"

# === PAM SSHD setup ===
PAM_FILE="/etc/pam.d/sshd"
LINE_TO_ADD="session required pam_exec.so $DEST_SCRIPT"

if ! grep -Fxq "$LINE_TO_ADD" "$PAM_FILE"; then
    echo "$LINE_TO_ADD" >> "$PAM_FILE"
    echo "✅ PAM SSHD updated."
else
    echo "ℹ️ PAM SSHD already configured."
fi

echo "✅ SSH login Telegram notifications configured successfully!"
