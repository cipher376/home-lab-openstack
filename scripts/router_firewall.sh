#!/bin/sh

# 1. Define the Interface (Change 'br-lan.10' if your device name is different)
MGMT_IF="br-lan.10"

echo "Configuring Firewall Zone for OpenStack Management..."

# 2. Create the MGMT Zone
uci set firewall.mgmt=zone
uci set firewall.mgmt.name='mgmt'
uci set firewall.mgmt.input='REJECT'
uci set firewall.mgmt.output='ACCEPT'
uci set firewall.mgmt.forward='REJECT'
uci add_list firewall.mgmt.device="$MGMT_IF"

# 3. Allow LAN to access MGMT (So your workstation can SSH/Ping nodes)
uci set firewall.lan_to_mgmt=forwarding
uci set firewall.lan_to_mgmt.src='lan'
uci set firewall.lan_to_mgmt.dest='mgmt'

# 4. Allow ICMP (Ping) to the Router from MGMT (For health checks)
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-MGMT-Ping'
uci set firewall.@rule[-1].src='mgmt'
uci set firewall.@rule[-1].proto='icmp'
uci set firewall.@rule[-1].target='ACCEPT'

# 5. Optimization: VRRP NOTRACK (Bypass conntrack for Kolla VIP traffic)
# This prevents the "dropped by kernel" issues you saw earlier
uci set firewall.vrrp_notrack=raw
uci set firewall.vrrp_notrack.name='Ignore_VRRP_Noise'
uci set firewall.vrrp_notrack.src='mgmt'
uci set firewall.vrrp_notrack.proto='112'
uci set firewall.vrrp_notrack.target='NOTRACK'

# 6. Apply Changes
echo "Committing changes and restarting firewall..."
uci commit firewall
/etc/init.d/firewall restart

echo "Done! VLAN 10 is now in the 'mgmt' zone."