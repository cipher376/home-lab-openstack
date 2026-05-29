#!/bin/bash

set -e

echo "=== Stopping Cinder services ==="
sudo systemctl stop kolla-cinder-volume || true
sudo systemctl disable kolla-cinder-volume || true

echo "=== Removing logical volumes ==="
sudo lvremove -f cinder-volumes-nvme-ssd/cinder-volumes-nvme-ssd-pool 2>/dev/null || true
sudo lvremove -f cinder-volumes-hdd/cinder-volumes-hdd-pool 2>/dev/null || true
sudo lvremove -f cinder-volumes-sata-ssd/cinder-volumes-sata-ssd-pool 2>/dev/null || true

echo "=== Removing volume groups ==="
sudo vgremove -f cinder-volumes-nvme-ssd 2>/dev/null || true
sudo vgremove -f cinder-volumes-hdd 2>/dev/null || true
sudo vgremove -f cinder-volumes-sata-ssd 2>/dev/null || true

echo "=== Removing physical volumes ==="
sudo pvremove -f /dev/nvme0n1p2 2>/dev/null || true
sudo pvremove -f /dev/sda2 2>/dev/null || true
sudo pvremove -f /dev/sdb3 2>/dev/null || true

echo "=== Wiping partitions ==="
sudo dd if=/dev/zero of=/dev/nvme0n1p2 bs=1M count=10 2>/dev/null
sudo dd if=/dev/zero of=/dev/sda2 bs=1M count=10 2>/dev/null
sudo dd if=/dev/zero of=/dev/sdb3 bs=1M count=10 2>/dev/null

echo "=== Recreating physical volumes ==="
sudo pvcreate /dev/nvme0n1p2
sudo pvcreate /dev/sda2
sudo pvcreate /dev/sdb3

echo "=== Recreating volume groups ==="
sudo vgcreate cinder-volumes-nvme-ssd /dev/nvme0n1p2
sudo vgcreate cinder-volumes-hdd /dev/sda2
sudo vgcreate cinder-volumes-sata-ssd /dev/sdb3

echo "=== Recreating thin pools ==="
sudo lvcreate -L 3.43T -T cinder-volumes-nvme-ssd/cinder-volumes-nvme-ssd-pool
sudo lvcreate -L 2.85T -T cinder-volumes-hdd/cinder-volumes-hdd-pool
sudo lvcreate -L 131G -T cinder-volumes-sata-ssd/cinder-volumes-sata-ssd-pool

echo "=== Verification ==="
sudo vgs
sudo lvs
sudo pvs

echo "=== Done! ==="
echo "Now run on your deployment host:"
echo "  kolla-ansible -i ./all-in-one reconfigure --tags cinder"