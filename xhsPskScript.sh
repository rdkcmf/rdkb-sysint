#!/bin/sh

psk=""

#Retrieve Auth Key
if [ -s  /etc/icontrol/cyavtfjzx.pse ] ; then

	mkdir -p /tmp/icontrol
	/usr/bin/configparamgen jx /etc/icontrol/cyavtfjzx.pse /tmp/icontrol/cyavtfjzx.pse
	authkey=`/bin/cat /tmp/icontrol/cyavtfjzx.pse`
fi

if [ -n  "$authkey" ] ; then

	#Retrieve CM MAC
	cmMAC=$(dmcli eRT getv Device.DeviceInfo.X_COMCAST-COM_CM_MAC  | grep "value:" | awk '{ print $5 }' | tr -d ' ' )
	
	#Calculate PSK
	if [ -n  "$cmMAC" ] ; then
		psk=$(/usr/sbin/icontrolkey -m $cmMAC -p $authkey )
	fi
fi

#Cleanup
if [ -e  /tmp/icontrol/cyavtfjzx.pse ] ; then
	authkey=""
	/bin/rm -rf /tmp/icontrol/cyavtfjzx.pse
fi

echo $psk
