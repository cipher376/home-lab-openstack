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