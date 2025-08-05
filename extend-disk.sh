#!/bin/bash

set -e

echo 1 > /sys/block/sda/device/rescan

# Detect root partition and disk
ROOT_PART=$(findmnt -n -o SOURCE /)
DISK=${ROOT_PART%[0-9]*}
[[ "$DISK" == *"p" ]] && DISK=${ROOT_PART%p[0-9]*}
PART_NUM=$(echo "$ROOT_PART" | grep -o '[0-9]*$')

# Install growpart if missing
command -v growpart >/dev/null 2>&1 || {
    if command -v apt >/dev/null; then
        apt update -qq && apt install -y -qq cloud-guest-utils
    elif command -v yum >/dev/null; then
        yum install -y -q cloud-utils-growpart
    else
        echo "growpart not found and package manager unsupported."
        exit 1
    fi
}

# Rescan partition table
partprobe "$DISK" || blockdev --rereadpt "$DISK"

# Grow the partition
growpart "$DISK" "$PART_NUM"

# Resize filesystem
FSTYPE=$(lsblk -no FSTYPE "$ROOT_PART")
[ "$FSTYPE" = "xfs" ] && xfs_growfs / || resize2fs "$ROOT_PART"
