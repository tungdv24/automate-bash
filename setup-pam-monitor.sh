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
DEST_SCRIPT="/etc/pam.script"

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
LINE_TO_ADD="session optional pam_exec.so /etc/pam.script"

if ! grep -Fxq "$LINE_TO_ADD" "$PAM_FILE"; then
    echo "$LINE_TO_ADD" >> "$PAM_FILE"
    echo "✅ PAM SSHD updated."
else
    echo "ℹ️ PAM SSHD already configured."
fi

echo "✅ SSH login Telegram notifications configured successfully!"
