#!/bin/sh
# This script is used tp log the up/down stream traffic for private network
# zhicheng_qiu@cable.comcast.com

source /fss/gw/etc/utopia/service.d/log_env_var.sh

ARMCONSOLEFILE="ArmConsolelog.txt.0"

BIN_PATH=/fss/gw/usr/ccsp 
if mkdir $lockdir; then
  #success
  echo $$ > $lockdir/PID
else
  exit 6
fi

# RDKB-6628 : Periodically log whether SSIDs are same or not
ssid24value=""
ssid5value=""
got_24=0
got_5=0
getSsid24=`dmcli eRT getv Device.WiFi.SSID.1.SSID`
getSsid5=`dmcli eRT getv Device.WiFi.SSID.2.SSID`

# Get 2.4GHz SSID and do sanity check
SSID_24=`echo $getSsid24 | grep "Execution succeed"`
if [ "$SSID_24" == "" ]
then
    echo "`date +'%Y-%m-%d:%H:%M:%S:%6N'` [RDKB_PLATFORM_ERROR] Didn't get WiFi 2.4 GHz SSID from agent" >> $LOG_PATH/$ARMCONSOLEFILE
else
    ssid24value=`echo $getSsid24 | cut -f6 -d:`
    got_24=1
fi

# Get 5GHz SSID and do sanity check
SSID_5=`echo $getSsid5 | grep "Execution succeed"`
if [ "$SSID_5" == "" ]
then
    echo "`date +'%Y-%m-%d:%H:%M:%S:%6N'` [RDKB_PLATFORM_ERROR] Didn't get WiFi 5 GHz SSID from agent" >> $LOG_PATH/$ARMCONSOLEFILE
else
    ssid5value=`echo $getSsid5 | cut -f6 -d:`
    got_5=1
fi

# Compare 2.4GHz and 5GHz SSID and log
if [ $got_24 -eq 1 ] && [ $got_5 -eq 1 ]
then
     if [ "$ssid5value" == "$ssid24value" ]
     then
        echo "`date +'%Y-%m-%d:%H:%M:%S:%6N'` [RDKB_STAT_LOG] 2.4G and 5G SSIDs are same" >> $LOG_PATH/$ARMCONSOLEFILE
     else
        echo "`date +'%Y-%m-%d:%H:%M:%S:%6N'` [RDKB_STAT_LOG] 2.4G and 5G SSIDs are different" >> $LOG_PATH/$ARMCONSOLEFILE
     fi
     got_24=0
     got_5=0 
fi
# RDKB-6628 Ends here

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

