#!/bin/sh
# Configure masquerading, so containers can reach the internet
iptables -t nat -A POSTROUTING -s ${NET_CIRD} -o eth0 -j MASQUERADE

# Override the default nameserver, otherwise performance on OSX sucks
#cat << EOF > /etc/resolv.conf
#nameserver 8.8.8.8
#EOF