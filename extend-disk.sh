#!/bin/bash

set -euo pipefail

echo ">>> Rescanning disk..."
echo 1 > /sys/block/sda/device/rescan

# Detect root partition and disk
ROOT_PART=$(findmnt -n -o SOURCE /)
DISK=${ROOT_PART%[0-9]*}
[[ "$DISK" == *"p" ]] && DISK=${ROOT_PART%p[0-9]*}
PART_NUM=$(echo "$ROOT_PART" | grep -o '[0-9]*$')

# Determine OS family
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_FAMILY=$ID
else
    echo "Cannot detect OS."
    exit 1
fi

# Check and install growpart
ensure_growpart() {
    if ! command -v growpart &>/dev/null; then
        echo ">>> Installing growpart..."
        if command -v apt &>/dev/null; then
            apt update -qq || { echo "apt update failed"; exit 1; }
            apt install -y -qq cloud-guest-utils
        elif command -v yum &>/dev/null || command -v dnf &>/dev/null; then
            yum install -y -q cloud-utils-growpart || dnf install -y cloud-utils-growpart
        else
            echo "No supported package manager found to install growpart."
            exit 1
        fi
    fi
}

# Ensure required tools are available
require_tool() {
    local tool="$1"
    command -v "$tool" >/dev/null || {
        echo "Missing required tool: $tool"
        exit 1
    }
}

# Install dependencies
ensure_growpart
require_tool partprobe || require_tool blockdev
require_tool lsblk

# Rescan partition table
echo ">>> Rescanning partition table..."
if command -v partprobe &>/dev/null; then
    partprobe "$DISK"
else
    blockdev --rereadpt "$DISK"
fi

# Grow the partition
echo ">>> Growing partition $DISK $PART_NUM..."
growpart "$DISK" "$PART_NUM"

# Resize filesystem
FSTYPE=$(lsblk -no FSTYPE "$ROOT_PART")
echo ">>> Resizing filesystem ($FSTYPE)..."
case "$FSTYPE" in
    xfs)
        require_tool xfs_growfs
        xfs_growfs /
        ;;
    ext4|ext3|ext2)
        require_tool resize2fs
        resize2fs "$ROOT_PART"
        ;;
    *)
        echo "Unsupported filesystem type: $FSTYPE"
        exit 1
        ;;
esac

echo "✅ Disk resized successfully."
