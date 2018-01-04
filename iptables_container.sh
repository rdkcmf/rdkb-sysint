#!/bin/sh

####################################################################################
# If not stated otherwise in this file or this component's Licenses.txt file the
# following copyright and licenses apply:
#
#  Copyright 2018 RDK Management
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##################################################################################


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
/usr/sbin/iptables -t nat -A PREROUTING -i eth0.4090 -p tcp -d 192.168.251.254 --dport 21515 -m conntrack --ctstate NEW  -j DNAT --to-destination $CONTAINER_LIGHTTPD_IP:21515
/usr/sbin/iptables -t nat -A PREROUTING -i $LXC_BRIDGE_NAME -p tcp -d 192.168.251.254 --dport 21515 -m conntrack --ctstate NEW -j DNAT --to-destination $CONTAINER_LIGHTTPD_IP:21515
/usr/sbin/iptables -t nat -A OUTPUT -p tcp -d 192.168.251.254 -m conntrack --ctstate NEW --dport 21515 -j DNAT --to-destination $CONTAINER_LIGHTTPD_IP:21515
/usr/sbin/iptables -t nat -A POSTROUTING --out-interface eth0.500 -j MASQUERADE
fi
