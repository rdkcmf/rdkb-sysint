#!/bin/sh -

/usr/sbin/iptables -t nat -A POSTROUTING -o lxcbr0 -j MASQUERADE
/usr/sbin/iptables -t nat -A PREROUTING -i eth0.4090 -p tcp -d 192.168.251.254 --dport 80 -m conntrack --ctstate NEW  -j DNAT --to-destination \$CONTAINER_LIGHTTPD_IP:80
/usr/sbin/iptables -t nat -A PREROUTING -i lxcbr0 -p tcp -d 192.168.251.254 --dport 80 -m conntrack --ctstate NEW -j DNAT --to-destination \$CONTAINER_LIGHTTPD_IP:80
/usr/sbin/iptables -t nat -A OUTPUT -p tcp -d 192.168.251.254 -m conntrack --ctstate NEW --dport 80 -j DNAT --to-destination \$CONTAINER_LIGHTTPD_IP:80
/usr/sbin/iptables -t nat -A PREROUTING -i eth0.4090 -p tcp -d 192.168.251.254 --dport 51515 -m conntrack --ctstate NEW  -j DNAT --to-destination \$CONTAINER_LIGHTTPD_IP:51515
/usr/sbin/iptables -t nat -A PREROUTING -i lxcbr0 -p tcp -d 192.168.251.254 --dport 51515 -m conntrack --ctstate NEW -j DNAT --to-destination \$CONTAINER_LIGHTTPD_IP:51515
/usr/sbin/iptables -t nat -A OUTPUT -p tcp -d 192.168.251.254 -m conntrack --ctstate NEW --dport 51515 -j DNAT --to-destination \$CONTAINER_LIGHTTPD_IP:51515
/usr/sbin/iptables -t nat -A POSTROUTING --out-interface eth0.500 -j MASQUERADE
