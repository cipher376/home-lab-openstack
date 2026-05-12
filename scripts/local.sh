sudo dnf update -y
sudo dnf install -y python3-virtualenv python3-devel gcc libffi-devel openssl-devel git sshpass

# Create and activate virtual environment
virtualenv ~/kolla-venv
source ~/kolla-venv/bin/activate

# Upgrade pip and install Kolla-Ansible
pip install --upgrade pip
pip install 'ansible-core>=2.15,<2.17.0'  # Fedora works well with newer Ansible
pip install git+https://opendev.org/openstack/kolla-ansible@stable/2024.2




# Check if SELinux is blocking Ansible
sudo ausearch -m avc -ts recent

# If you see denials, temporarily set permissive for the deployment session
# (This affects ONLY the workstation, not the OpenStack nodes)
sudo setenforce 0

# Or permanently allow Ansible Python to connect out (preferred)
sudo setsebool -P httpd_can_network_connect 1
sudo setsebool -P nis_enabled 1



# Run on nodes to prepare storage volumes
sudo vgcreate cinder-volumes /dev/sda3 /dev/sdb
sudo vgcreate cinder-volumes /dev/sdb  # Change sdb to your storage disk



openstack volume type create fast-ssd
openstack volume type set --property volume_backend_name=SSD_Storage fast-ssd

# Generate key on workstation if you don't have one
ssh-keygen -t ed25519

# Copy key to all three nodes (adjust IPs)
ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
ssh-copy-id ubuntu@node-01.lan  # Node 1
ssh-copy-id ubuntu@node-02.lan  # Node 2
ssh-copy-id ubuntu@node-03.lan  # Node 3



kolla-ansible bootstrap-servers -i ./multinode
kolla-ansible prechecks -i ./multinode
kolla-ansible pull -i ./multinode
kolla-ansible deploy -i ./multinode


curl -s -H "X-Auth-Token: $TOKEN" \
     -H "OpenStack-API-Version: placement 1.0" \
     "$PLACEMENT/resource_providers/70e1e721-2be3-4fa3-9515-30bcf8f951a7/inventories" | python3 -m json.tool



#============================================================================================================
#============================================================================================================
#============================================================================================================


     Then update the flavor:
bashsource /etc/kolla/admin-openrc.sh

# Create GPU flavor
openstack flavor create gpu.1 \
  --ram 16384 \
  --vcpus 8 \
  --disk 80 \
  --public

# Set PCI alias
openstack flavor set gpu.1 \
  --property "pci_passthrough:alias"="gpu6gb:1"
Then test launch a VM:
bashopenstack server create \
  --flavor gpu.1 \
  --image <your-image> \
  --network <your-network> \
  --availability-zone nova \
  gpu-test-01no image let's create one02:31Let's download a lightweight cloud image and upload it to Glance:
bash# Download Ubuntu 22.04 cloud image
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# Upload to Glance
source /etc/kolla/admin-openrc.sh

openstack image create "Ubuntu-22.04" \
  --file jammy-server-cloudimg-amd64.img \
  --disk-format qcow2 \
  --container-format bare \
  --public

# Verify
openstack image list
Once uploaded, launch the GPU VM:
bashopenstack server create \
  --flavor gpu.1 \
  --image "Ubuntu-22.04" \
  --network <your-network-name> \
  gpu-test-01
Get your network name first:
bashopenstack network listno network02:34Let's create the network first:
bashsource /etc/kolla/admin-openrc.sh

# Create private network
openstack network create private

# Create subnet
openstack subnet create private-subnet \
  --network private \
  --subnet-range 192.168.100.0/24 \
  --gateway 192.168.100.1 \
  --dns-nameserver 8.8.8.8

# Create router
openstack router create main-router

# Attach subnet to router
openstack router add subnet main-router private-subnet
Then check if you have an external/provider network for floating IPs:
bashopenstack network list
If there's no external network yet, create one — what's the external network range in your home lab? Based on your setup it looks like 172.16.0.0/24, so:
bash# Create external network (admin only)
openstack network create public \
  --external \
  --provider-network-type flat \
  --provider-physical-network physnet1

openstack subnet create public-subnet \
  --network public \
  --subnet-range 172.16.0.0/24 \
  --gateway 172.16.0.1 \
  --allocation-pool start=172.16.0.200,end=172.16.0.220 \
  --no-dhcp

# Set router external gateway
openstack router set main-router --external-gateway public
Then launch the VM:
bashopenstack server create \
  --flavor gpu.1 \
  --image "Ubuntu-22.04" \
  --network private \
  gpu-test-01



  # Get your project ID
PROJECT_ID=$(openstack project show admin -f value -c id)

# Increase cores and RAM quota
openstack quota set \
  --cores 100 \
  --ram 102400 \
  --instances 20 \
  $PROJECT_ID

# Verify
openstack quota show $PROJECT_ID | grep -E "cores|ram|instances"


openstack server show gpu-test-05 | grep fault

#============================================================
#============================================================
#============================================================

# Get the VM's IP
openstack server show gpu-test-07 | grep addresses

# SSH in (you may need a floating IP first)
openstack floating ip create public
openstack server add floating ip gpu-test-07 <floating-ip>

ssh ubuntu@<floating-ip> "lspci | grep -i nvidia"




network:
  version: 2
  ethernets:
    ens5:
      dhcp4: no

  vlans:
    vlan10:
      id: 10
      link: ens5
      dhcp4: no
      addresses:
        - 172.16.0.20/24
      routes:
        - to: default
          via: 172.16.0.1
      nameservers:
        addresses: [172.16.0.1, 8.8.8.8, 1.1.1.1]
    vlan20:
      id: 20
      link: ens5
      dhcp4: no


# ========================================================
# ========================================================
# ========================================================
source /etc/kolla/admin-openrc.sh

# Remove old floating IP and router gateway
openstack server remove floating ip gpu-test-07 172.16.0.202
openstack floating ip delete 172.16.0.202
openstack router unset main-router --external-gateway

# Delete old public network
openstack subnet delete public-subnet
openstack network delete public

# Create new external network on vlan20
openstack network create public \
  --external \
  --provider-network-type vlan \
  --provider-physical-network physnet1 \
  --provider-segment 20

openstack subnet create public-subnet \
  --network public \
  --subnet-range 172.16.100.0/24 \
  --gateway 172.16.100.1 \
  --allocation-pool start=172.16.100.100,end=172.16.100.200 \
  --no-dhcp

# Restore router gateway
openstack router set main-router --external-gateway public

# Create new floating IP
openstack floating ip create public

NS=$(sudo ip netns list | grep qrouter | awk '{print $1}')
sudo ip netns exec $NS tcpdump -i any -n -e -c20 &


openstack network create private
openstack subnet create private-subnet --network private \
  --subnet-range 10.0.0.0/24 --gateway 10.0.0.1



  #Adding custom routes 
  # Outgoing: Traffic from Router (Port 1) -> Tag 20 -> eno1 (Port 3)
docker exec openvswitch_vswitchd ovs-ofctl add-flow br-ex "priority=100,in_port=1,actions=mod_vlan_vid:20,output:3"

# Incoming: Traffic from OpenWrt (Port 3) with VLAN 20 -> Strip Tag -> Router (Port 1)
docker exec openvswitch_vswitchd ovs-ofctl add-flow br-ex "priority=100,in_port=3,dl_vlan=20,actions=strip_vlan,output:1"


# 1. Delete the failed node
openstack server delete gpu-prod-01

# 2. Recreate with the --config-drive flag
openstack server create --flavor gpu.1 \
  --image Ubuntu-22.04 \
  --network private \
  --security-group ai-cluster-sg \
  --key-name lab-key \
  --config-drive true \
  --user-data ./gpu-bootstrap.yaml \
  gpu-prod-01

# 3. Wait for ACTIVE, then re-assign your Floating IP
openstack server add floating ip gpu-prod-01 172.16.100.135


 docker exec -u root neutron_openvswitch_agent ovs-ofctl show br-int
 sudo docker exec -it neutron_openvswitch_agent ovs-tcpdump -i eno1 icmp

# Capture ICMP on phy-br-ex (Internal Patch from VMs)
sudo docker exec -it neutron_openvswitch_agent ovs-tcpdump -i phy-br-ex icmp
# Allow VLAN 10 to behave like a normal switch (this handles the 'reroute')
sudo docker exec -u root -it neutron_openvswitch_agent ovs-ofctl add-flow br-ex "priority=100,dl_vlan=10,actions=NORMAL"

# Ensure the patch port still allows traffic meant for the internal integration bridge
sudo docker exec -u root -it neutron_openvswitch_agent ovs-ofctl add-flow br-ex "priority=101,in_port=7,dl_vlan=10,actions=NORMAL"

sudo docker exec -u root -it neutron_openvswitch_agent ovs-ofctl add-flow br-ex "priority=2000,dl_type=0x0806,dl_vlan=10,actions=NORMAL"
sudo docker exec -u root -it neutron_openvswitch_agent ovs-vsctl show 
sudo docker exec -u root -it neutron_openvswitch_agent ovs-ofctl show br-ex
sudo docker exec -u root -it neutron_openvswitch_agent ovs-ofctl show br-int
watch -n 2 'sudo docker exec -u root -it neutron_openvswitch_agent ovs-ofctl dump-flows br-int | grep "int-br-ex"'
watch -n 2 'sudo docker exec -u root -it neutron_openvswitch_agent ovs-ofctl dump-flows br-ex | grep "phy-br-ex"'
sudo docker exec -u root -it neutron_openvswitch_agent ovs-vsctl del-port br-ex vlan20
sudo docker exec -u root -it neutron_openvswitch_agent ovs-vsctl del-port br-ex vlan30
docker exec -u  root -it neutron_openvswitch_agent ovs-vsctl set Port vlan20 trunks=20
docker exec -u root -it neutron_openvswitch_agent ovs-ofctl add-flow br-ex "priority=10,in_port=phy-br-ex,actions=strip_vlan,output:1"
