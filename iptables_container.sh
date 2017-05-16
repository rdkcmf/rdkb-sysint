#!/bin/sh
. /etc/device.properties

if [ "x$LXC_BRIDGE_NAME" = "x" ]; then
  #Default value of LXC_BRIDGE
  LXC_BRIDGE_NAME=lxclink0
fi

if [ "x$CONTAINER_LIGHTTPD_IP" != "x" ]; then
/usr/sbin/iptables -t nat -A POSTROUTING -o $LXC_BRIDGE_NAME -j MASQUERADE
/usr/sbin/iptables -t nat -A PREROUTING -i eth0.4090 -p tcp -d 192.168.251.254 --dport 80 -m conntrack --ctstate NEW  -j DNAT --to-destination $CONTAINER_LIGHTTPD_IP:80
/usr/sbin/iptables -t nat -A PREROUTING -i $LXC_BRIDGE_NAME -p tcp -d 192.168.251.254 --dport 80 -m conntrack --ctstate NEW -j DNAT --to-destination $CONTAINER_LIGHTTPD_IP:80
/usr/sbin/iptables -t nat -A OUTPUT -p tcp -d 192.168.251.254 -m conntrack --ctstate NEW --dport 80 -j DNAT --to-destination $CONTAINER_LIGHTTPD_IP:80
/usr/sbin/iptables -t nat -A PREROUTING -i eth0.4090 -p tcp -d 192.168.251.254 --dport 51515 -m conntrack --ctstate NEW  -j DNAT --to-destination $CONTAINER_LIGHTTPD_IP:51515
/usr/sbin/iptables -t nat -A PREROUTING -i $LXC_BRIDGE_NAME -p tcp -d 192.168.251.254 --dport 51515 -m conntrack --ctstate NEW -j DNAT --to-destination $CONTAINER_LIGHTTPD_IP:51515
/usr/sbin/iptables -t nat -A OUTPUT -p tcp -d 192.168.251.254 -m conntrack --ctstate NEW --dport 51515 -j DNAT --to-destination $CONTAINER_LIGHTTPD_IP:51515
/usr/sbin/iptables -t nat -A POSTROUTING --out-interface eth0.500 -j MASQUERADE
fi
