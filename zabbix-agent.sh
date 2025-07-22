#!/bin/bash

set -e

# Defaults
ZBX_SERVER="192.168.10.196"
ZBX_VERSION="7.0"

# Parse arguments
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
        *)
            echo "Usage: $0 [--server <zabbix_server_ip>] [--version <zabbix_version>]"
            exit 1
            ;;
    esac
done

echo ">>> Installing Zabbix Agent ${ZBX_VERSION} with Server ${ZBX_SERVER}"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_FAMILY=$ID
else
    echo "Cannot detect OS"
    exit 1
fi

install_agent_ubuntu() {
    echo ">>> Installing Zabbix Agent on Ubuntu/Debian"
    apt-get update -y
    apt-get install -y wget gnupg2 lsb-release

    wget https://repo.zabbix.com/zabbix/${ZBX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZBX_VERSION}-1+$(lsb_release -cs)_all.deb
    dpkg -i zabbix-release_${ZBX_VERSION}-1+$(lsb_release -cs)_all.deb
    apt-get update -y
    apt-get install -y zabbix-agent2
}

install_agent_centos() {
    echo ">>> Installing Zabbix Agent on CentOS/RHEL"
    yum install -y wget
    rpm -Uvh https://repo.zabbix.com/zabbix/${ZBX_VERSION}/rhel/$(rpm -E %{rhel})/x86_64/zabbix-release-${ZBX_VERSION}-1.el$(rpm -E %{rhel}).noarch.rpm
    yum clean all
    yum install -y zabbix-agent2
}

configure_agent() {
    echo ">>> Configuring Zabbix Agent"
    ZBX_CONF="/etc/zabbix/zabbix_agent2.conf"
    if [ ! -f "$ZBX_CONF" ]; then
        echo "Zabbix Agent config not found!"
        exit 1
    fi

    sed -i "s/^Server=.*/Server=$ZBX_SERVER/" $ZBX_CONF
    sed -i "s/^ServerActive=.*/ServerActive=$ZBX_SERVER/" $ZBX_CONF
}

start_agent() {
    echo ">>> Enabling and restarting Zabbix Agent"
    systemctl enable zabbix-agent2
    systemctl restart zabbix-agent2
    systemctl status zabbix-agent2 --no-pager
}

case "$OS_FAMILY" in
    ubuntu|debian)
        install_agent_ubuntu
        ;;
    centos|rhel|rocky|almalinux)
        install_agent_centos
        ;;
    *)
        echo "Unsupported OS: $OS_FAMILY"
        exit 1
        ;;
esac

configure_agent
start_agent

echo ">>> Zabbix Agent v${ZBX_VERSION} installation and configuration completed successfully."
