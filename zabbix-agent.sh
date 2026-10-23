#!/bin/bash
set -euo pipefail

# ==============================================================================
# Script: zabbix-agent.sh
# Purpose: Automated installation and configuration of Zabbix Agent 1 or 2
#          on Ubuntu, Debian, CentOS, RHEL, Rocky Linux, and AlmaLinux.
# ==============================================================================

# Ensure root privileges
if [[ $EUID -ne 0 ]]; then
    echo "❌ Error: This script must be run as root or with sudo."
    exit 1
fi

# Default values
ZBX_SERVER="192.168.10.196"
ZBX_VERSION="7.0"
ZBX_AGENT="1"  # Default to agent 1

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --server|-s)
            ZBX_SERVER="$2"
            shift 2
            ;;
        --version|-v)
            ZBX_VERSION="$2"
            shift 2
            ;;
        --ver|-a|--agent)
            ZBX_AGENT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: sudo $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -s, --server <ip>      Zabbix Server IP (default: 192.168.10.196)"
            echo "  -v, --version <ver>    Zabbix Version, e.g. 7.0, 6.4, 6.0 (default: 7.0)"
            echo "  -a, --ver <1|2>        Zabbix Agent version: 1 or 2 (default: 1)"
            echo "  -h, --help             Show this help message"
            exit 0
            ;;
        *)
            echo "❌ Unknown argument: $1"
            echo "Usage: sudo $0 [--server <ip>] [--version <ver>] [--ver <1|2>]"
            exit 1
            ;;
    esac
done

if [[ "$ZBX_AGENT" != "1" && "$ZBX_AGENT" != "2" ]]; then
    echo "❌ Error: Invalid agent version '$ZBX_AGENT'. Must be 1 or 2."
    exit 1
fi

echo "=========================================================="
echo "          Zabbix Agent Installation & Setup               "
echo "=========================================================="
echo "Zabbix Server : $ZBX_SERVER"
echo "Zabbix Version: $ZBX_VERSION"
echo "Agent Version : Zabbix Agent $ZBX_AGENT"
echo "=========================================================="

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_FAMILY=$ID
else
    echo "❌ Error: Cannot detect operating system."
    exit 1
fi

check_selinux_disabled() {
    if command -v getenforce &>/dev/null; then
        ENFORCE_STATUS=$(getenforce)
        if [[ "$ENFORCE_STATUS" == "Enforcing" ]]; then
            echo "⚠️  SELinux is currently Enforcing. This may block Zabbix agent metrics."
            echo "   To avoid issues, consider setting SELinux to Permissive or Disabled."
        fi
    fi
}

check_package_manager_update() {
    echo ">>> [1/4] Updating package manager cache..."
    if [[ "$OS_FAMILY" =~ ^(ubuntu|debian)$ ]]; then
        apt-get update -qq || {
            echo "❌ apt-get update failed. Check network or repository settings."
            exit 1
        }
    elif [[ "$OS_FAMILY" =~ ^(centos|rhel|rocky|almalinux|ol)$ ]]; then
        if command -v dnf &>/dev/null; then
            dnf makecache -q || true
        else
            yum makecache -q || true
        fi
    fi
}

install_agent_debian_ubuntu() {
    echo ">>> [2/4] Setting up Zabbix repository on Debian/Ubuntu..."
    apt-get install -y -qq wget gnupg2 ca-certificates lsb-release

    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    CODENAME=$(lsb_release -cs 2>/dev/null || echo "")

    if [[ "$OS_FAMILY" == "ubuntu" ]]; then
        case "$CODENAME" in
            focal)  DIST_TAG="ubuntu20.04" ;;
            jammy)  DIST_TAG="ubuntu22.04" ;;
            noble)  DIST_TAG="ubuntu24.04" ;;
            bionic) DIST_TAG="ubuntu18.04" ;;
            *)
                echo "❌ Unsupported Ubuntu version: $CODENAME"
                exit 1
                ;;
        esac
        REPO_DEB="zabbix-release_${ZBX_VERSION}-1+${DIST_TAG}_all.deb"
        REPO_URL="https://repo.zabbix.com/zabbix/${ZBX_VERSION}/ubuntu/pool/main/z/zabbix-release/${REPO_DEB}"

    elif [[ "$OS_FAMILY" == "debian" ]]; then
        case "$CODENAME" in
            bookworm) DEB_VER="12" ;;
            bullseye) DEB_VER="11" ;;
            buster)   DEB_VER="10" ;;
            *)
                DEB_VER=$(cut -d. -f1 /etc/debian_version 2>/dev/null || echo "")
                ;;
        esac
        REPO_DEB="zabbix-release_${ZBX_VERSION}-1+debian${DEB_VER}_all.deb"
        REPO_URL="https://repo.zabbix.com/zabbix/${ZBX_VERSION}/debian/pool/main/z/zabbix-release/${REPO_DEB}"
    fi

    echo ">>> Downloading $REPO_URL..."
    wget -q -O "$TMP_DIR/$REPO_DEB" "$REPO_URL" || {
        echo "❌ Failed to download Zabbix release deb. Check version '$ZBX_VERSION'."
        exit 1
    }
    dpkg -i "$TMP_DIR/$REPO_DEB" >/dev/null
    apt-get update -qq

    echo ">>> [3/4] Installing Zabbix Agent..."
    if [ "$ZBX_AGENT" = "2" ]; then
        apt-get install -y -qq zabbix-agent2
    else
        apt-get install -y -qq zabbix-agent
    fi
}

install_agent_rhel() {
    echo ">>> [2/4] Setting up Zabbix repository on RHEL/CentOS..."
    PKG_MGR="yum"
    command -v dnf &>/dev/null && PKG_MGR="dnf"

    $PKG_MGR install -y -q wget ca-certificates

    RHEL_MAJOR=$(rpm -E %{rhel} 2>/dev/null || echo "")
    if [[ -z "$RHEL_MAJOR" || "$RHEL_MAJOR" == "%{rhel}" ]]; then
        RHEL_MAJOR=$(grep -oE '[0-9]+' /etc/redhat-release | head -n1 || echo "8")
    fi

    case "$RHEL_MAJOR" in
        7|8|9|10) ;;
        *)
            echo "❌ Unsupported RHEL major version: $RHEL_MAJOR"
            exit 1
            ;;
    esac

    REPO_URL="https://repo.zabbix.com/zabbix/${ZBX_VERSION}/rhel/${RHEL_MAJOR}/x86_64/zabbix-release-${ZBX_VERSION}-1.el${RHEL_MAJOR}.noarch.rpm"
    echo ">>> Installing repository RPM: $REPO_URL"
    rpm -Uvh --replacepkgs "$REPO_URL" || true
    $PKG_MGR clean metadata -q 2>/dev/null || true

    echo ">>> [3/4] Installing Zabbix Agent..."
    if [ "$ZBX_AGENT" = "2" ]; then
        $PKG_MGR install -y -q zabbix-agent2
    else
        $PKG_MGR install -y -q zabbix-agent
    fi
}

configure_agent() {
    echo ">>> [4/4] Configuring Zabbix Agent parameters..."
    if [ "$ZBX_AGENT" = "2" ]; then
        ZBX_CONF="/etc/zabbix/zabbix_agent2.conf"
    else
        ZBX_CONF="/etc/zabbix/zabbix_agentd.conf"
    fi

    if [ ! -f "$ZBX_CONF" ]; then
        echo "❌ Error: Config file not found at $ZBX_CONF"
        exit 1
    fi

    # Update Server and ServerActive
    sed -i "s|^Server=.*|Server=$ZBX_SERVER|" "$ZBX_CONF"
    sed -i "s|^ServerActive=.*|ServerActive=$ZBX_SERVER|" "$ZBX_CONF"

    # Set Hostname if default
    CURRENT_HOST=$(hostname -s 2>/dev/null || hostname)
    if grep -q "^Hostname=Zabbix server" "$ZBX_CONF"; then
        sed -i "s|^Hostname=Zabbix server|Hostname=$CURRENT_HOST|" "$ZBX_CONF"
    fi

    echo "✅ Updated $ZBX_CONF (Server: $ZBX_SERVER, ServerActive: $ZBX_SERVER)"
}

start_agent() {
    SERVICE_NAME="zabbix-agent"
    [[ "$ZBX_AGENT" == "2" ]] && SERVICE_NAME="zabbix-agent2"

    echo ">>> Starting and enabling $SERVICE_NAME..."
    systemctl enable "$SERVICE_NAME" &>/dev/null || true
    systemctl restart "$SERVICE_NAME"

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "✅ Service '$SERVICE_NAME' is active and running!"
    else
        echo "❌ Error: Service '$SERVICE_NAME' failed to start."
        systemctl status "$SERVICE_NAME" --no-pager || true
        exit 1
    fi
}

# === Execution Flow ===
check_package_manager_update

case "$OS_FAMILY" in
    ubuntu|debian)
        install_agent_debian_ubuntu
        ;;
    centos|rhel|rocky|almalinux|ol|fedora)
        check_selinux_disabled
        install_agent_rhel
        ;;
    *)
        echo "❌ Unsupported OS: $OS_FAMILY"
        exit 1
        ;;
esac

configure_agent
start_agent

echo "=========================================================="
echo "🎉 Zabbix Agent $ZBX_AGENT (v$ZBX_VERSION) successfully installed!"
echo "   Server IP : $ZBX_SERVER"
echo "   Hostname  : $(hostname)"
echo "=========================================================="
