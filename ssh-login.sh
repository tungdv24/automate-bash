#!/bin/bash

# Telegram Bot configuration
telegrambot=""
telegramchatid=""
thread_id=""

# Telegram API URL
url="https://api.telegram.org/bot$telegrambot/sendMessage"
date="$(date "+%T_%F")"

# Output file for logs
output_file="/usr/local/sbin/file.txt"

# IP Whitelist
whitelist=("60.191.67.90" "103.53.170.145" "113.190.242.72" "118.70.144.69" "103.53.170.132")

# Check if PAM_RHOST is in the whitelist
if [[ " ${whitelist[@]} " =~ " ${PAM_RHOST} " ]]; then
    is_whitelisted=true
else
    is_whitelisted=false
fi


## Push notification
if [ "$is_whitelisted" = true ] && [ "$PAM_TYPE" != "close_session" ]; then
    message=$(printf "✅ New SSH connection \"<b>%s</b>@%s_%s\" from ip address %s at %s" "$PAM_USER" "$(hostname)" "$(hostname -I | awk '{print $1}')" "$PAM_RHOST" "$date")
    curl -X POST "$url" -d chat_id=$telegramchatid -d text="$message" -d parse_mode="HTML" -d parse_mode="HTML" -d message_thread_id="$thread_id" > /dev/null
    echo "$message" >> "$output_file"
elif [ "$is_whitelisted" = false ] && [ "$PAM_TYPE" != "close_session" ]; then
    message=$(printf "👻 New SSH connection \"<b>%s</b>@%s_%s\" from ip address %s at %s" "$PAM_USER" "$(hostname)" "$(hostname -I | awk '{print $1}')" "$PAM_RHOST" "$date")
    curl -X POST "$url" -d chat_id=$telegramchatid -d text="$message" -d parse_mode="HTML" -d parse_mode="HTML" -d message_thread_id="$thread_id" > /dev/null
    echo "$message" >> "$output_file"
elif [ "$PAM_TYPE" = "close_session" ]; then
    message=$(printf "🔚 Logout SSH \"<b>%s</b>@%s_%s\" from ip address %s at %s" "$PAM_USER" "$(hostname)" "$(hostname -I | awk '{print $1}')" "$PAM_RHOST" "$date")
    curl -X POST "$url" -d chat_id=$telegramchatid -d text="$message" -d parse_mode="HTML" -d parse_mode="HTML" -d message_thread_id="$thread_id" > /dev/null
    echo "$message" >> "$output_file"
fi