#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_BASE_URL="https://raw.githubusercontent.com/tungdv24/automate-bash/main"

# Helper function to run script locally if available, or fetch from GitHub
run_subscript() {
    local script_name="$1"
    local run_as_sudo="$2"
    shift 2

    local local_file="$SCRIPT_DIR/$script_name"
    local runner=""
    [[ "$run_as_sudo" == "true" ]] && runner="sudo"

    if [[ -f "$local_file" ]]; then
        echo -e "\n📁 Running local script: $local_file\n"
        $runner bash "$local_file" "$@"
    else
        local remote_url="$REPO_BASE_URL/$script_name"
        echo -e "\n🌐 Fetching and running from GitHub: $remote_url\n"
        $runner bash <(curl -fsSL "$remote_url") "$@"
    fi
}

while true; do
  clear
  echo "=========================================================="
  echo "               Automate Bash Admin Toolkit                "
  echo "=========================================================="
  echo " 1)  Add sudo user with SSH key"
  echo " 2)  Add SSH monitor Telegram alert"
  echo " 3)  Install Zabbix Agent"
  echo " 4)  Install Zabbix Config"
  echo " 5)  Extend Disk & Filesystem (growpart/LVM)"
  echo " 6)  Firewall Manager (UFW / Firewalld)"
  echo " 7)  Execute command on multiple servers"
  echo " 8)  Sequential SSH sessions"
  echo " 9)  Network & Ping/Traceroute Checker"
  echo " 10) Setup Data Disk (/data)"
  echo " 11) Exit"
  echo "=========================================================="
  read -p "Select an option [1-11]: " choice

  case $choice in
    1)
      read -p "Enter username: " username
      echo "Paste the SSH public key (end with ENTER then CTRL+D):"
      ssh_key=$(</dev/stdin)

      if [[ -z "$username" || -z "$ssh_key" ]]; then
        echo "❌ Username or key is empty. Aborting."
        read -p "Press ENTER to continue..."
        continue
      fi

      run_subscript "add_sudo_user.sh" "true" --user "$username" --key "$ssh_key"
      read -p "Press ENTER to return to menu..."
      ;;

    2)
      read -p "Enter Bot Token: " bot_token
      read -p "Enter Chat ID: " chat_id
      read -p "Enter Thread ID (optional): " thread_id

      if [[ -z "$bot_token" || -z "$chat_id" ]]; then
        echo "❌ Bot token or chat ID is missing. Aborting."
        read -p "Press ENTER to continue..."
        continue
      fi

      if [[ -n "$thread_id" ]]; then
        run_subscript "setup-pam-monitor.sh" "true" "$bot_token" "$chat_id" "$thread_id"
      else
        run_subscript "setup-pam-monitor.sh" "true" "$bot_token" "$chat_id"
      fi
      read -p "Press ENTER to return to menu..."
      ;;

    3)
      ZBX_SERVER="192.168.10.196"
      ZBX_VERSION="7.0"
      ZBX_AGENT="1"

      read -p "Enter Zabbix Server IP [$ZBX_SERVER]: " input_server
      read -p "Enter Zabbix Version (e.g., 7.0, 6.4) [$ZBX_VERSION]: " input_ver
      read -p "Enter Agent Ver (1 or 2) [$ZBX_AGENT]: " input_agent

      server_ip="${input_server:-$ZBX_SERVER}"
      zbx_version="${input_ver:-$ZBX_VERSION}"
      agent_ver="${input_agent:-$ZBX_AGENT}"

      run_subscript "zabbix-agent.sh" "true" --server "$server_ip" --version "$zbx_version" --ver "$agent_ver"
      read -p "Press ENTER to return to menu..."
      ;;

    4)
      run_subscript "zabbix-config.sh" "true"
      read -p "Press ENTER to return to menu..."
      ;;

    5)
      run_subscript "extend-disk.sh" "true"
      read -p "Press ENTER to return to menu..."
      ;;

    6)
      run_subscript "firewall.sh" "true"
      read -p "Press ENTER to return to menu..."
      ;;

    7)
      run_subscript "execute-cmd.sh" "false"
      read -p "Press ENTER to return to menu..."
      ;;

    8)
      run_subscript "ssh-session.sh" "false"
      read -p "Press ENTER to return to menu..."
      ;;

    9)
      run_subscript "network-check.sh" "true"
      read -p "Press ENTER to return to menu..."
      ;;

    10)
      run_subscript "setup-data-disk.sh" "true"
      read -p "Press ENTER to return to menu..."
      ;;

    11)
      echo "Goodbye!"
      exit 0
      ;;

    *)
      echo "❌ Invalid choice: $choice"
      read -p "Press ENTER to try again..."
      ;;
  esac
done
