#!/bin/bash
set -euo pipefail

# ==============================================================================
# Script: setup-data-disk.sh
# Purpose: Scan for secondary disk (e.g., /dev/sdb, /dev/vdb, /dev/nvme1n1),
#          prevent touching root disk, partition (GPT), format (ext4/xfs),
#          mount, and persist to /etc/fstab with UUID.
# ==============================================================================

DISK="/dev/sdb"
MOUNT_POINT="/data"
FS_TYPE="ext4"
FORCE=0

# Parse optional arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk|-d)
            DISK="$2"
            shift 2
            ;;
        --mount|-m)
            MOUNT_POINT="$2"
            shift 2
            ;;
        --fs)
            FS_TYPE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=1
            shift
            ;;
        -h|--help)
            echo "Usage: sudo $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -d, --disk <dev>    Target disk (default: /dev/sdb, e.g. /dev/vdb, /dev/nvme1n1)"
            echo "  -m, --mount <path>  Mount point directory (default: /data)"
            echo "      --fs <type>     Filesystem type: ext4 or xfs (default: ext4)"
            echo "  -f, --force         Force wipe and reformat even if not empty"
            echo "  -h, --help          Show this help message"
            exit 0
            ;;
        *)
            echo "❌ Unknown argument: $1"
            echo "Use -h or --help for usage."
            exit 1
            ;;
    esac
done

# Ensure root privileges
if [[ $EUID -ne 0 ]]; then
    echo "❌ Error: This script must be run as root or with sudo."
    exit 1
fi

echo "=========================================================="
echo "          New VM Data Disk Setup Script                   "
echo "=========================================================="
echo "Target Disk : $DISK"
echo "Mount Point : $MOUNT_POINT"
echo "Filesystem  : $FS_TYPE"
echo "Force Wipe  : $([[ $FORCE -eq 1 ]] && echo 'YES' || echo 'NO')"
echo "=========================================================="

# 1. Rescan SCSI buses and block devices to discover newly attached disks
echo ">>> [1/7] Rescanning storage buses for newly attached disks..."
for host in /sys/class/scsi_host/*; do
    if [[ -d "$host" ]]; then
        echo "- - -" > "$host/scan" 2>/dev/null || true
    fi
done
for rescan_dev in /sys/block/*/device/rescan; do
    if [[ -f "$rescan_dev" ]]; then
        echo 1 > "$rescan_dev" 2>/dev/null || true
    fi
done
udevadm settle 2>/dev/null || true

# 2. Check if the block device exists
if [[ ! -b "$DISK" ]]; then
    echo "❌ Error: Block device '$DISK' was not found."
    if [[ -b "/dev/vdb" ]]; then
        echo "ℹ️  Found '/dev/vdb' instead (VirtIO block device)."
        echo "   Re-run with: sudo $0 --disk /dev/vdb"
    elif [[ -b "/dev/nvme1n1" ]]; then
        echo "ℹ️  Found '/dev/nvme1n1' instead (NVMe block device)."
        echo "   Re-run with: sudo $0 --disk /dev/nvme1n1"
    fi
    echo "   Please attach the secondary disk to the VM and try again."
    exit 1
fi

# Safety check: Protect Root Disk from accidental wipe
ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null || true)
ROOT_PARENT=$(lsblk -no PKNAME "$ROOT_DEV" 2>/dev/null | head -n1 || true)
[[ -z "$ROOT_PARENT" && -b "$ROOT_DEV" ]] && ROOT_PARENT=$(basename "$ROOT_DEV")

DISK_BASE=$(basename "$DISK")
if [[ -n "$ROOT_PARENT" && "$DISK_BASE" == "$ROOT_PARENT"* ]]; then
    echo "❌ CRITICAL SAFETY ERROR: Disk '$DISK' contains the root (/) filesystem!"
    echo "   Refusing to partition or format the system root disk."
    exit 1
fi

DISK_SIZE=$(lsblk -dn -o SIZE "$DISK" 2>/dev/null || echo "Unknown")
echo "✅ Found disk: $DISK (Size: $DISK_SIZE)"

# Determine partition naming scheme (e.g. /dev/sdb1 vs /dev/nvme0n1p1)
if [[ "$DISK" =~ [0-9]$ ]]; then
    PART_PREFIX="p"
else
    PART_PREFIX=""
fi
PART1="${DISK}${PART_PREFIX}1"

# 3. Check if mount point or disk is already mounted
echo ">>> [2/7] Checking mount status..."

# Check if mount point is already mounted
if findmnt -M "$MOUNT_POINT" &>/dev/null; then
    CURRENT_SOURCE=$(findmnt -n -o SOURCE "$MOUNT_POINT")
    echo "ℹ️  Mount point '$MOUNT_POINT' is already mounted on '$CURRENT_SOURCE'."
    if [[ "$CURRENT_SOURCE" == "$DISK"* ]]; then
        echo "✅ '$DISK' is already mounted to '$MOUNT_POINT'."
        # Ensure fstab is configured
        TARGET_PART="$CURRENT_SOURCE"
        UUID=$(blkid -s UUID -o value "$TARGET_PART" 2>/dev/null || lsblk -no UUID "$TARGET_PART" 2>/dev/null || true)
        if [[ -n "$UUID" ]] && ! grep -q "$UUID" /etc/fstab; then
            echo ">>> Adding missing entry to /etc/fstab..."
            echo -e "UUID=$UUID\t$MOUNT_POINT\t$FS_TYPE\tdefaults,nofail\t0\t2" >> /etc/fstab
            echo "✅ Added UUID=$UUID to /etc/fstab"
        fi
        exit 0
    else
        echo "❌ Error: '$MOUNT_POINT' is already mounted by a different device ($CURRENT_SOURCE)."
        exit 1
    fi
fi

# Check if the disk or any partition is mounted elsewhere
MOUNTED_WHERE=$(lsblk -no MOUNTPOINT "$DISK" 2>/dev/null | grep -v '^$' || true)
if [[ -n "$MOUNTED_WHERE" ]]; then
    echo "❌ Error: '$DISK' or one of its partitions is already mounted on: $MOUNTED_WHERE"
    echo "   Unmount it first before running this script."
    exit 1
fi

# 4. Check if disk is empty
echo ">>> [3/7] Inspecting disk contents and signatures..."
PART_COUNT=$(lsblk -r -n -o TYPE "$DISK" | grep -c "part" || true)
DISK_FSTYPE=$(lsblk -no FSTYPE "$DISK" | grep -v '^$' | head -n1 || true)
BLK_ID_OUT=$(blkid "$DISK"* 2>/dev/null || true)

TARGET_PART=""

if [[ $PART_COUNT -gt 0 || -n "$DISK_FSTYPE" || -n "$BLK_ID_OUT" ]]; then
    echo "⚠️  Disk '$DISK' is NOT empty:"
    lsblk -o NAME,SIZE,FSTYPE,TYPE "$DISK"

    if [[ $FORCE -eq 1 ]]; then
        echo "⚠️  --force specified: Wiping all partition tables and filesystem signatures..."
        wipefs -a -f "$DISK"
        if command -v sgdisk &>/dev/null; then
            sgdisk --zap-all "$DISK" 2>/dev/null || true
        fi
        partprobe "$DISK" 2>/dev/null || true
        udevadm settle 2>/dev/null || true
        sleep 1
    else
        # If partition 1 exists with a filesystem, preserve data and mount safely
        if [[ -b "$PART1" ]]; then
            PART1_FSTYPE=$(lsblk -no FSTYPE "$PART1" 2>/dev/null || true)
            if [[ -n "$PART1_FSTYPE" ]]; then
                echo "ℹ️  Found existing filesystem ($PART1_FSTYPE) on '$PART1'."
                echo ">>> Using existing partition '$PART1' without formatting to preserve data."
                TARGET_PART="$PART1"
                FS_TYPE="$PART1_FSTYPE"
            fi
        fi

        if [[ -z "$TARGET_PART" ]]; then
            echo "❌ Aborting: Disk contains existing data or partitions."
            echo "   To overwrite and reformat the entire disk, re-run with: sudo $0 --disk $DISK --force"
            exit 1
        fi
    fi
fi

# 5. Create partition if not already set
if [[ -z "$TARGET_PART" ]]; then
    echo ">>> [4/7] Partitioning $DISK (GPT primary partition)..."
    if command -v parted &>/dev/null; then
        parted -s "$DISK" mklabel gpt mkpart primary "$FS_TYPE" 0% 100%
    elif command -v sfdisk &>/dev/null; then
        printf "label: gpt\n,\n" | sfdisk "$DISK"
    else
        echo -e "g\nn\n1\n\n\nw" | fdisk "$DISK"
    fi

    partprobe "$DISK" 2>/dev/null || true
    udevadm settle 2>/dev/null || true
    sleep 1

    TARGET_PART="$PART1"
    if [[ ! -b "$TARGET_PART" ]]; then
        blockdev --rereadpt "$DISK" 2>/dev/null || true
        sleep 1
    fi

    if [[ ! -b "$TARGET_PART" ]]; then
        echo "❌ Error: Partition '$TARGET_PART' was not detected after partitioning."
        exit 1
    fi

    echo "✅ Created partition: $TARGET_PART"

    # Ensure formatting tools are available
    case "$FS_TYPE" in
        ext4|ext3)
            if ! command -v mkfs.ext4 &>/dev/null; then
                echo ">>> Installing e2fsprogs..."
                if command -v apt-get &>/dev/null; then
                    apt-get install -y -qq e2fsprogs
                else
                    yum install -y -q e2fsprogs || dnf install -y -q e2fsprogs
                fi
            fi
            echo ">>> [5/7] Formatting $TARGET_PART with ext4..."
            mkfs.ext4 -F -q "$TARGET_PART"
            ;;
        xfs)
            if ! command -v mkfs.xfs &>/dev/null; then
                echo ">>> Installing xfsprogs..."
                if command -v apt-get &>/dev/null; then
                    apt-get install -y -qq xfsprogs
                else
                    yum install -y -q xfsprogs || dnf install -y -q xfsprogs
                fi
            fi
            echo ">>> [5/7] Formatting $TARGET_PART with xfs..."
            mkfs.xfs -f -q "$TARGET_PART"
            ;;
        *)
            echo "⚠️  Unsupported filesystem: $FS_TYPE. Defaulting to ext4."
            mkfs.ext4 -F -q "$TARGET_PART"
            FS_TYPE="ext4"
            ;;
    esac
    echo "✅ Formatted $TARGET_PART as $FS_TYPE"
else
    echo ">>> [4/7] Skipping partitioning (using existing $TARGET_PART)..."
    echo ">>> [5/7] Skipping format to preserve existing filesystem..."
fi

# 6. Create mount point and mount
echo ">>> [6/7] Creating mount point '$MOUNT_POINT' and mounting..."
mkdir -p "$MOUNT_POINT"
mount "$TARGET_PART" "$MOUNT_POINT"
chmod 755 "$MOUNT_POINT"
echo "✅ Successfully mounted $TARGET_PART to $MOUNT_POINT"

# 7. Add entry to /etc/fstab using UUID
echo ">>> [7/7] Configuring /etc/fstab with UUID..."
udevadm settle 2>/dev/null || true
UUID=$(blkid -s UUID -o value "$TARGET_PART" 2>/dev/null || lsblk -no UUID "$TARGET_PART" 2>/dev/null || true)

if [[ -n "$UUID" ]]; then
    FSTAB_IDENTIFIER="UUID=$UUID"
else
    echo "⚠️  Warning: Could not retrieve UUID for $TARGET_PART. Falling back to device path."
    FSTAB_IDENTIFIER="$TARGET_PART"
fi

# Backup /etc/fstab
BACKUP_FSTAB="/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
cp /etc/fstab "$BACKUP_FSTAB"
echo "ℹ️  Created fstab backup: $BACKUP_FSTAB"

# Check if mount point or UUID already exists in /etc/fstab
if [[ -n "$UUID" ]] && grep -q "$UUID" /etc/fstab; then
    echo "ℹ️  Entry for $UUID already exists in /etc/fstab."
elif grep -E "[[:space:]]+${MOUNT_POINT}[[:space:]]+" /etc/fstab &>/dev/null; then
    echo "ℹ️  Commenting out previous entry for '$MOUNT_POINT' in /etc/fstab..."
    sed -i -E "s|^([^#].*[[:space:]]+${MOUNT_POINT}[[:space:]]+.*)|# \1 # disabled by setup-data-disk.sh|" /etc/fstab
    FSTAB_LINE="${FSTAB_IDENTIFIER}    ${MOUNT_POINT}    ${FS_TYPE}    defaults,nofail    0    2"
    echo "$FSTAB_LINE" >> /etc/fstab
    echo "✅ Appended to /etc/fstab: $FSTAB_LINE"
else
    FSTAB_LINE="${FSTAB_IDENTIFIER}    ${MOUNT_POINT}    ${FS_TYPE}    defaults,nofail    0    2"
    echo "$FSTAB_LINE" >> /etc/fstab
    echo "✅ Appended to /etc/fstab: $FSTAB_LINE"
fi

# Validate /etc/fstab syntax
echo ">>> Verifying /etc/fstab..."
mount -a
echo "✅ /etc/fstab verified successfully."

echo "=========================================================="
echo "🎉 Data disk setup completed successfully!"
echo "=========================================================="
df -h "$MOUNT_POINT"
echo "----------------------------------------------------------"
lsblk "$DISK"
echo "=========================================================="
