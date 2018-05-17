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

mac=`ifconfig eth0 | grep HWaddr | awk '{ print $5 }'`
first_octet=`echo $mac | awk -F ':' '{print $1}'`
first_octet_xor_2=`printf '%#x\n' "$((0x$first_octet ^ 0x2))" | sed 's/^0x//'`
ip=`awk -F ':' '{ temp=$2":"$3"ff:fe"$4":"$5$6; print temp }' <<< "$mac"`
ipv6_link_local="fe80::"$first_octet_xor_2$ip
ipv6_global="2301:db8:1:0:"$first_octet_xor_2$ip

ip addr add $ipv6_link_local/64 dev eth0
ip addr add $ipv6_global/64 dev eth0
ip route add default via 2301:db8:1::1 dev eth0
