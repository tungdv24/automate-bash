#!/bin/bash
set -e

# Default values
ZBX_SERVER="192.168.10.196"
ZBX_VERSION="7.0"
ZBX_AGENT="1"  # default to agent1

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --server)
            ZBX_SERVER="$2"
            shift 2
            ;;
        --version)
            ZBX_VERSION="$2"
            shift 2
            ;;
        --ver)
            ZBX_AGENT="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 [--server <zabbix_server_ip>] [--version <zabbix_version>] [--ver <1|2>]"
            exit 1
            ;;
    esac
done

echo ">>> Installing Zabbix Agent${ZBX_AGENT} ${ZBX_VERSION} with Server ${ZBX_SERVER}"

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_FAMILY=$ID
else
    echo "❌ Cannot detect OS"
    exit 1
fi

check_selinux_disabled() {
    if command -v getenforce &>/dev/null; then
        ENFORCE_STATUS=$(getenforce)
        if [[ "$ENFORCE_STATUS" != "Disabled" ]]; then
            echo "❌ SELinux is $ENFORCE_STATUS. Please disable it before continuing."
            exit 1
        fi
    fi
}

check_package_manager_update() {
    if [[ "$OS_FAMILY" =~ (ubuntu|debian) ]]; then
        echo ">>> Checking apt-get update..."
        if ! apt-get update -y; then
            echo "❌ apt-get update failed. Please check your internet connection or repository settings."
            exit 1
        fi
    elif [[ "$OS_FAMILY" =~ (centos|rhel|rocky|almalinux) ]]; then
        echo ">>> Checking yum update..."
        if ! yum -y update --nobest >/dev/null 2>&1; then
            echo "❌ yum update failed. Please check your internet connection or repository settings."
            exit 1
        fi
    fi
}

install_agent_ubuntu() {
    echo ">>> Installing Zabbix Agent on Ubuntu/Debian"

    apt-get install -y wget gnupg2 lsb-release

    # Map Ubuntu codename to Zabbix repo naming
    case "$(lsb_release -cs)" in
        focal)
            UBUNTU_VER="ubuntu20.04"
            ;;
        jammy)
            UBUNTU_VER="ubuntu22.04"
            ;;
        noble)
            UBUNTU_VER="ubuntu24.04"
            ;;
        *)
            echo "❌ Unsupported Ubuntu version: $(lsb_release -cs)"
            exit 1
            ;;
    esac

    wget https://repo.zabbix.com/zabbix/${ZBX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZBX_VERSION}-1+${UBUNTU_VER}_all.deb
    dpkg -i zabbix-release_${ZBX_VERSION}-1+${UBUNTU_VER}_all.deb
    apt-get update -y

    if [ "$ZBX_AGENT" = "2" ]; then
        apt-get install -y zabbix-agent2
    else
        apt-get install -y zabbix-agent
    fi
}

install_agent_centos() {
    echo ">>> Installing Zabbix Agent on CentOS/RHEL"

    yum install -y wget

    RHEL_MAJOR=$(rpm -E %{rhel})

    case "$RHEL_MAJOR" in
        8|9|10)
            ;;
        *)
            echo "❌ Unsupported RHEL major version: $RHEL_MAJOR"
            exit 1
            ;;
    esac

    rpm -Uvh https://repo.zabbix.com/zabbix/${ZBX_VERSION}/rhel/${RHEL_MAJOR}/x86_64/zabbix-release-${ZBX_VERSION}-1.el${RHEL_MAJOR}.noarch.rpm
    yum clean all

    if [ "$ZBX_AGENT" = "2" ]; then
        yum install -y zabbix-agent2
    else
        yum install -y zabbix-agent
    fi
}

configure_agent() {
    echo ">>> Configuring Zabbix Agent"
    if [ "$ZBX_AGENT" = "2" ]; then
        ZBX_CONF="/etc/zabbix/zabbix_agent2.conf"
    else
        ZBX_CONF="/etc/zabbix/zabbix_agentd.conf"
    fi

    if [ ! -f "$ZBX_CONF" ]; then
        echo "❌ Zabbix Agent config not found!"
        exit 1
    fi

    sed -i "s/^Server=.*/Server=$ZBX_SERVER/" "$ZBX_CONF"
    sed -i "s/^ServerActive=.*/ServerActive=$ZBX_SERVER/" "$ZBX_CONF"
}

start_agent() {
    echo ">>> Enabling and restarting Zabbix Agent"
    if [ "$ZBX_AGENT" = "2" ]; then
        systemctl enable zabbix-agent2
        systemctl restart zabbix-agent2
        systemctl status zabbix-agent2 --no-pager
    else
        systemctl enable zabbix-agent
        systemctl restart zabbix-agent
        systemctl status zabbix-agent --no-pager
    fi
}

# === Run steps ===
check_package_manager_update

case "$OS_FAMILY" in
    ubuntu|debian)
        install_agent_ubuntu
        ;;
    centos|rhel|rocky|almalinux)
        check_selinux_disabled
        install_agent_centos
        ;;
    *)
        echo "❌ Unsupported OS: $OS_FAMILY"
        exit 1
        ;;
esac

configure_agent
start_agent

echo "✅ Zabbix Agent${ZBX_AGENT} v${ZBX_VERSION} installation and configuration completed successfully."
