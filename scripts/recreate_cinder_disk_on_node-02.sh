#!/bin/bash

# Complete NVMe disk cleanup and recreation for Cinder
# This will wipe /dev/nvme0n1 and recreate it for Cinder use

set -e

echo "========================================="
echo "NVMe Disk Cleanup and Recreation for Cinder"
echo "========================================="
echo ""
echo "WARNING: This will DESTROY ALL DATA on /dev/nvme0n1"
echo "Disk size: 476.9 GB"
echo ""
read -p "Type 'yes' to continue: " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "=== Step 1: Stopping Cinder services that might use this disk ==="
sudo systemctl stop kolla-cinder-volume 2>/dev/null || true
sudo systemctl stop cinder-volume 2>/dev/null || true

echo ""
echo "=== Step 2: Removing LVM volumes on the disk ==="
# Remove logical volumes
sudo lvremove -f cinder-volumes-nvme-ssd/cinder-volumes-nvme-ssd-pool 2>/dev/null || true
sudo lvremove -f cinder-volumes-nvme-ssd 2>/dev/null || true

# Remove volume group
sudo vgremove -f cinder-volumes-nvme-ssd 2>/dev/null || true

# Remove physical volumes (both p1 and p2 if they exist)
sudo pvremove -f /dev/nvme0n1p2 2>/dev/null || true
sudo pvremove -f /dev/nvme0n1p1 2>/dev/null || true

echo ""
echo "=== Step 3: Completely wiping the NVMe disk ==="
# Remove all partition tables and signatures
sudo wipefs -a /dev/nvme0n1

# Zero out the first 100MB to ensure clean state
sudo dd if=/dev/zero of=/dev/nvme0n1 bs=1M count=100 status=progress

# Also zero out the last 10MB (where backup GPT table might be)
sudo dd if=/dev/zero of=/dev/nvme0n1 bs=1M count=10 seek=$(($(sudo blockdev --getsz /dev/nvme0n1) / 2048 - 10)) 2>/dev/null || true

echo ""
echo "=== Step 4: Creating new partition table ==="
# Create GPT partition table
sudo parted /dev/nvme0n1 mklabel gpt

# Wait for partition table to be updated
sudo partprobe /dev/nvme0n1
sleep 2

echo ""
echo "=== Step 5: Creating new partition (100% of disk) ==="
# Create single partition using all available space
sudo parted /dev/nvme0n1 mkpart primary 0% 100%

# Set the partition type for LVM (optional but good practice)
sudo parted /dev/nvme0n1 set 1 lvm on

# Inform kernel of partition changes
sudo partprobe /dev/nvme0n1
sleep 2

echo ""
echo "=== Step 6: Verifying new partition ==="
sudo lsblk /dev/nvme0n1
sudo fdisk -l /dev/nvme0n1 | grep nvme0n1

# Get the exact size of the new partition
PART_SIZE=$(sudo blockdev --getsz /dev/nvme0n1p1)
echo "New partition size: $PART_SIZE sectors"

echo ""
echo "=== Step 7: Creating physical volume ==="
# Create physical volume on the new partition
sudo pvcreate /dev/nvme0n1p1

echo ""
echo "=== Step 8: Creating volume group ==="
# Create volume group for Cinder
sudo vgcreate cinder-volumes-nvme-ssd /dev/nvme0n1p1

echo ""
echo "=== Step 9: Getting available size for thin pool ==="
# Get the available size in GB (use 95% of total for pool)
VG_SIZE=$(sudo vgdisplay cinder-volumes-nvme-ssd | grep "VG Size" | awk '{print $3}')
echo "Volume group size: $VG_SIZE GB"

# Calculate 95% of the size
POOL_SIZE_RAW=$(echo "$VG_SIZE * 0.95" | bc)
POOL_SIZE=$(printf "%.0f" $POOL_SIZE_RAW)
echo "Creating thin pool with size: ${POOL_SIZE}G"

echo ""
echo "=== Step 10: Creating thin pool logical volume ==="
# Create thin pool with optimal settings for NVMe
# Using 512K chunk size (good balance for NVMe)
sudo lvcreate -l 95%VG -T cinder-volumes-nvme-ssd/cinder-volumes-nvme-ssd-pool -c 512K
echo ""
echo "=== Step 11: Verification ==="
echo ""
echo "Physical Volumes:"
sudo pvs
echo ""
echo "Volume Groups:"
sudo vgs
echo ""
echo "Logical Volumes:"
sudo lvs
echo ""
echo "Detailed logical volume info:"
sudo lvdisplay cinder-volumes-nvme-ssd/cinder-volumes-nvme-ssd-pool

echo ""
echo "=== Step 12: Disk usage check ==="
df -h | grep -E "Filesystem|cinder"

echo ""
echo "========================================="
echo "✅ NVMe Disk Successfully Recreated for Cinder!"
echo "========================================="
echo ""
echo "Summary:"
echo "  - Disk: /dev/nvme0n1"
echo "  - Partition: /dev/nvme0n1p1"
echo "  - Volume Group: cinder-volumes-nvme-ssd"
echo "  - Thin Pool: cinder-volumes-nvme-ssd/cinder-volumes-nvme-ssd-pool"
echo "  - Pool Size: ${POOL_SIZE}G"
echo ""
echo "Next steps:"
echo "1. On your deployment host, reconfigure Cinder:"
echo "   cd ~/Scripts/home-lab-openstack"
echo "   source venv/bin/activate"
echo "   kolla-ansible -i ./all-in-one reconfigure --tags cinder"
echo ""
echo "2. Verify Cinder is working:"
echo "   source /etc/kolla/admin-openrc.sh"
echo "   openstack volume create --size 1 test-volume"
echo "   openstack volume list"
echo ""
echo "3. On node-03, verify volumes are created:"
echo "   sudo lvs | grep volume"
echo "========================================="