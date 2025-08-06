#!/bin/bash

while true; do
  clear
  echo "============================"
  echo " Auto Admin Script v1.0"
  echo "============================"
  echo "1) Add sudo user with SSH key"
  echo "2) Add SSH monitor alert"
  echo "3) Install Zabbix Agent"
  echo "4) Install Zabbix Config"
  echo "5) Extend Disk"
  echo "6) Exit"
  echo "============================"
  read -p "Enter your choice: " choice

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

      curl_cmd="curl -sSL https://raw.githubusercontent.com/tungdv24/automate-bash/main/add_sudo_user.sh | bash -s -- --user $username --key \"$ssh_key\""
      echo -e "\nExecuting:\n$curl_cmd\n"
      eval $curl_cmd
      read -p "✅ Done. Press ENTER to continue..."
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

      if [[ -z "$thread_id" ]]; then
        monitor_cmd="bash <(curl -fsSL https://raw.githubusercontent.com/tungdv24/automate-bash/main/setup-pam-monitor.sh) \"$bot_token\" \"$chat_id\""
      else
        monitor_cmd="bash <(curl -fsSL https://raw.githubusercontent.com/tungdv24/automate-bash/main/setup-pam-monitor.sh) \"$bot_token\" \"$chat_id\" \"$thread_id\""
      fi

      echo -e "\nExecuting:\n$monitor_cmd\n"
      eval $monitor_cmd
      read -p "✅ SSH Monitor setup complete. Press ENTER to continue..."
      ;;
    3)
      read -p "Enter Zabbix Server IP: " server_ip
      read -p "Enter Zabbix Version (e.g., 7.0): " zbx_version
      read -p "Enter Agent Ver (optional, e.g., 2): " agent_ver

      if [[ -z "$server_ip" || -z "$zbx_version" ]]; then
        echo "❌ Server IP or Zabbix version is missing. Aborting."
        read -p "Press ENTER to continue..."
        continue
      fi

      if [[ -z "$agent_ver" ]]; then
        zabbix_cmd="curl -sSL https://raw.githubusercontent.com/tungdv24/automate-bash/main/zabbix-agent.sh | bash -s -- --server $server_ip --version $zbx_version"
      else
        zabbix_cmd="curl -sSL https://raw.githubusercontent.com/tungdv24/automate-bash/main/zabbix-agent.sh | bash -s -- --server $server_ip --version $zbx_version --ver $agent_ver"
      fi

      echo -e "\nExecuting:\n$zabbix_cmd\n"
      eval $zabbix_cmd
      read -p "✅ Zabbix Agent installation complete. Press ENTER to continue..."
      ;;
    4)
      echo -e "\nInstalling Zabbix Config...\n"
      zbx_cfg_cmd="bash <(curl -fsSL https://raw.githubusercontent.com/tungdv24/automate-bash/main/zabbix-config.sh)"
      echo -e "Executing:\n$zbx_cfg_cmd\n"
      eval $zbx_cfg_cmd
      read -p "✅ Zabbix Config installed. Press ENTER to continue..."
      ;;
    5)
      echo -e "\nExtending disk...\n"
      extend_cmd="curl -sSL https://raw.githubusercontent.com/tungdv24/automate-bash/main/extend-disk.sh | sudo bash"
      echo -e "Executing:\n$extend_cmd\n"
      eval $extend_cmd
      read -p "✅ Disk extension complete. Press ENTER to continue..."
      ;;
    6)
      echo "Bye!"
      exit 0
      ;;
    *)
      echo "Invalid choice."
      read -p "Press ENTER to try again..."
      ;;
  esac
done
