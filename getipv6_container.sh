#!/bin/sh

mac=`ifconfig eth0 | grep HWaddr | awk '{ print $5 }'`
first_octet=`echo $mac | awk -F ':' '{print $1}'`
first_octet_xor_2=`printf '%#x\n' "$((0x$first_octet ^ 0x2))" | sed 's/^0x//'`
ip=`awk -F ':' '{ temp=$2":"$3"ff:fe"$4":"$5$6; print temp }' <<< "$mac"`
ipv6_link_local="fe80::"$first_octet_xor_2$ip
ipv6_global="2301:db8:1:0:"$first_octet_xor_2$ip

ip addr add $ipv6_link_local/64 dev eth0
ip addr add $ipv6_global/64 dev eth0
ip route add default via 2301:db8:1::1 dev eth0
