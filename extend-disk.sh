#!/bin/bash
set -euo pipefail

# ==============================================================================
# Script: extend-disk.sh
# Purpose: Rescan disks, detect root filesystem (Standard partition or LVM),
#          grow the partition using growpart, and expand ext4/xfs filesystems.
# ==============================================================================

if [[ $EUID -ne 0 ]]; then
    echo "❌ Error: This script must be run as root or with sudo."
    exit 1
fi

echo "=========================================================="
echo "           Auto Disk & Filesystem Extension               "
echo "=========================================================="
echo ">>> Current root filesystem usage:"
df -h /
echo "=========================================================="

# 1. Rescan SCSI & block device buses for storage changes
echo ">>> [1/5] Rescanning storage buses and disks..."
for host in /sys/class/scsi_host/*; do
    if [[ -d "$host" ]]; then
        echo "- - -" > "$host/scan" 2>/dev/null || true
    fi
done

for dev in /sys/block/*/device/rescan; do
    if [[ -f "$dev" ]]; then
        echo 1 > "$dev" 2>/dev/null || true
    fi
done
udevadm settle 2>/dev/null || true

# 2. Detect root mount device
echo ">>> [2/5] Detecting root filesystem layout..."
ROOT_PART=$(findmnt -n -o SOURCE / 2>/dev/null || true)

if [[ -z "$ROOT_PART" ]]; then
    echo "❌ Error: Could not determine root mount device."
    exit 1
fi

echo "ℹ️  Root mount device: $ROOT_PART"

# Ensure growpart is installed
ensure_growpart() {
    if ! command -v growpart &>/dev/null; then
        echo ">>> Installing growpart..."
        if command -v apt-get &>/dev/null; then
            apt-get update -qq && apt-get install -y -qq cloud-guest-utils
        elif command -v dnf &>/dev/null; then
            dnf install -y -q cloud-utils-growpart
        elif command -v yum &>/dev/null; then
            yum install -y -q cloud-utils-growpart
        else
            echo "❌ No supported package manager found to install growpart."
            exit 1
        fi
    fi
}

ensure_growpart

DEV_TYPE=$(lsblk -no TYPE "$ROOT_PART" 2>/dev/null | head -n1 || echo "")
FSTYPE=$(lsblk -no FSTYPE "$ROOT_PART" 2>/dev/null | head -n1 || echo "")

# 3. Handle LVM vs Standard Partition
if [[ "$DEV_TYPE" == "lvm" ]]; then
    echo "ℹ️  Detected LVM volume for root filesystem."
    echo ">>> [3/5] Inspecting Physical Volumes (PV)..."

    # Find PV backing the root LV
    PV_NAME=""
    if command -v pvs &>/dev/null; then
        PV_NAME=$(pvs --noheadings -o pv_name 2>/dev/null | tr -d ' ' | head -n1 || true)
    fi

    if [[ -z "$PV_NAME" ]]; then
        PK_RAW=$(lsblk -no PKNAME "$ROOT_PART" 2>/dev/null | head -n1 || true)
        [[ -n "$PK_RAW" ]] && PV_NAME="/dev/$PK_RAW"
    fi

    if [[ -z "$PV_NAME" || ! -b "$PV_NAME" ]]; then
        echo "❌ Error: Could not detect Physical Volume for LVM $ROOT_PART."
        exit 1
    fi

    echo "ℹ️  Found Physical Volume: $PV_NAME"
    DISK_NAME=$(lsblk -no PKNAME "$PV_NAME" 2>/dev/null | head -n1 || true)
    if [[ -z "$DISK_NAME" ]]; then
        DISK=${PV_NAME%[0-9]*}
        [[ "$DISK" == *"p" ]] && DISK=${PV_NAME%p[0-9]*}
    else
        DISK="/dev/$DISK_NAME"
    fi

    PART_NUM=$(lsblk -no PARTN "$PV_NAME" 2>/dev/null | head -n1 || true)
    [[ -z "$PART_NUM" ]] && PART_NUM=$(echo "$PV_NAME" | grep -o '[0-9]*$')

    echo ">>> [4/5] Growing partition $DISK partition $PART_NUM..."
    growpart "$DISK" "$PART_NUM" 2>/dev/null || true

    echo ">>> Resizing Physical Volume $PV_NAME..."
    pvresize "$PV_NAME"

    echo ">>> [5/5] Extending Logical Volume and resizing filesystem ($FSTYPE)..."
    lvextend -r -l +100%FREE "$ROOT_PART"

else
    # Standard Raw Partition
    echo "ℹ️  Detected standard partition for root filesystem."
    DISK_NAME=$(lsblk -no PKNAME "$ROOT_PART" 2>/dev/null | head -n1 || true)

    if [[ -z "$DISK_NAME" ]]; then
        DISK=${ROOT_PART%[0-9]*}
        [[ "$DISK" == *"p" ]] && DISK=${ROOT_PART%p[0-9]*}
    else
        DISK="/dev/$DISK_NAME"
    fi

    PART_NUM=$(lsblk -no PARTN "$ROOT_PART" 2>/dev/null | head -n1 || true)
    [[ -z "$PART_NUM" ]] && PART_NUM=$(echo "$ROOT_PART" | grep -o '[0-9]*$')

    echo "ℹ️  Disk: $DISK, Partition Number: $PART_NUM"

    echo ">>> [3/5] Rescanning partition table for $DISK..."
    if command -v partprobe &>/dev/null; then
        partprobe "$DISK" 2>/dev/null || true
    else
        blockdev --rereadpt "$DISK" 2>/dev/null || true
    fi

    echo ">>> [4/5] Growing partition $DISK partition $PART_NUM..."
    growpart "$DISK" "$PART_NUM" 2>/dev/null || true

    echo ">>> [5/5] Resizing filesystem ($FSTYPE)..."
    case "$FSTYPE" in
        xfs)
            if command -v xfs_growfs &>/dev/null; then
                xfs_growfs /
            else
                echo "❌ Error: xfs_growfs command not found."
                exit 1
            fi
            ;;
        ext4|ext3|ext2)
            if command -v resize2fs &>/dev/null; then
                resize2fs "$ROOT_PART"
            else
                echo "❌ Error: resize2fs command not found."
                exit 1
            fi
            ;;
        *)
            echo "⚠️  Unsupported or unknown filesystem type: $FSTYPE"
            exit 1
            ;;
    esac
fi

echo "=========================================================="
echo "🎉 Root disk expansion completed successfully!"
echo "=========================================================="
df -h /
echo "=========================================================="
