#!/bin/sh
##########################################################################
# If not stated otherwise in this file or this component's Licenses.txt
# file the following copyright and licenses apply:
#
# Copyright 2016 RDK Management
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
##########################################################################
# This script is used tp log the up/down stream traffic for private network
# zhicheng_qiu@cable.comcast.com

source /fss/gw/etc/utopia/service.d/log_env_var.sh

BIN_PATH=/fss/gw/usr/ccsp 
if mkdir $lockdir; then
  #success
  echo $$ > $lockdir/PID
else
  exit 6
fi

t="RDKB_DataConsumption"
tm=`date "+%s"`
d=`date "+%s |%Y-%m-%d %H:%M:%S "`
x=`ifconfig brlan0 | grep "RX bytes" | tr '(' '|' | tr ':' '|' | cut -d'|' -f2,4`
rx=`echo $x | cut -d'|' -f1`;
tx=`echo $x | cut -d'|' -f2`;
tm_0=`cat /tmp/tm_0`
ct_0=`cat /tmp/ct_0`
rx_0=`cat /tmp/rx_0`
tx_0=`cat /tmp/tx_0` 
[[ -z "$tm_0" ]] &&	tm_0="0"
[[ -z "$ct_0" ]] &&	ct_0="0"
[[ -z "$rx_0" ]] &&	rx_0="0"
[[ -z "$tx_0" ]] &&	tx_0="0"
tm_d=$(($tm-$tm_0))

if [ "$tm_d" -gt "300" ]; then
	ct=$(($ct_0+1))
	echo $tm > /tmp/tm_0;
	echo $ct > /tmp/ct_0;
	echo $rx > /tmp/rx_0;
	echo $tx > /tmp/tx_0;

	#rx_d=$(($rx-$rx_0))
	rx_d=`$BIN_PATH/Sub64 $rx $rx_0`
	#tx_d=$(($tx-$tx_0))
	tx_d=`$BIN_PATH/Sub64 $tx $tx_0`
	echo "$t |$ct_0 |$d|$x|$rx_d |$tx_d " >> $LOG_PATH/RXTX100Log.txt

	t="RDKB_WiFiClientDrop"
	count=`dmcli eRT getv Device.Hosts.HostNumberOfEntries| grep type | cut -d':' -f3 | tr -d " "`
	witotoal="0";
	wlost="0";
	for i in `seq 1 $count`; do
		iface=`dmcli eRT getv Device.Hosts.Host.$i.Layer1Interface | grep type | cut -d':' -f3 | tr -d " "`
		if [ "$iface" == "Device.WiFi.SSID.1" ] || [ "$iface" == "Device.WiFi.SSID.2" ]; then
			witotoal=$(($witotoal+1));
			ip=`dmcli eRT getv Device.Hosts.Host.$i.IPAddress | grep type | cut -d':' -f3`
			res=`ping -c1 -W2 $ip | grep time`
			if [ -z "$res" ]; then
				wlost=$(($wlost+1));
			fi
		fi
	done
	echo "$t |$d|$witotoal |$wlost" >> $LOG_PATH/wificlientdrop.txt

fi

trap 'rm -r "$lockdir" >/dev/null 2>&1' 0
trap "exit 2" 1 2 3 13 15

