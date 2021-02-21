#!/bin/bash

## init transkript
exec &> >(tee -a "${0%.*}.log")

trace () {
    echo -e "\n>>> $@ ...\n"
}

## upgrade packages
trace "Upgrading packages"
apt-get update -y && unattended-upgrades

## enable IP forwarding
trace "Enabling IP forwarding"
sed -i -e 's/#net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sed -i -e 's/#net.ipv6.conf.all.forwarding.*/net.ipv6.conf.all.forwarding=1/g' /etc/sysctl.conf
sysctl -p

## install WireGurard
trace "Installing WireGuard"
add-apt-repository ppa:wireguard/wireguard -y && apt-get update -y 
apt-get install linux-headers-$(uname -r) wireguard -y

## generate security keys
trace "Generating private & public keys"
wg genkey | tee /etc/wireguard/server_privatekey | wg pubkey > /etc/wireguard/server_publickey
wg genkey | tee /etc/wireguard/client_privatekey | wg pubkey > /etc/wireguard/client_publickey

## create server config
trace "Generating server config"
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 10.200.200.1/24
SaveConfig = true
PrivateKey = $(cat /etc/wireguard/server_privatekey)
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = $(cat /etc/wireguard/client_publickey)
AllowedIPs = 0.0.0.0/0
EOF

trace "Generating client config"
cat > /etc/wireguard/wg0-client.conf << EOF
[Interface]
Address = 10.200.200.2/32
PrivateKey = $(cat /etc/wireguard/client_privatekey)
DNS = $(cat /etc/resolv.conf | grep -i '^nameserver' | head -n1 | cut -d ' ' -f2)

[Peer]
PublicKey = $(cat /etc/wireguard/server_publickey)
Endpoint = $(curl ifconf.co):51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 10
EOF

## make server config accessible
trace "Graning config access"
chmod 600 /etc/wireguard/{wg0.conf,wg0-client.conf}

## configure firewall
trace "Configuring firewall" 
ufw allow 51820/udp
ufw allow 22/tcp
ufw --force enable

# ## start WireGuard service
# wg-quick up wg0
# systemctl enable wg-quick@wg0

# ## system reboot
trace "Initiate system upgrade & reboot"
apt-get full-upgrade -y && shutdown -r 0
