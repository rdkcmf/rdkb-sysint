#!/bin/sh

retVal=""

#Retrieve Parameter2
if [ -s  /etc/xhs/cyavtfjzx.pse ] ; then

	mkdir -p /tmp/xhs
	/usr/bin/configparamgen jx /etc/xhs/cyavtfjzx.pse /tmp/xhs/cyavtfjzx.pse
	param2=`/bin/cat /tmp/xhs/cyavtfjzx.pse`
fi

if [ -n  "$param2" ] ; then

	#Retrieve CM MAC
	cmMAC=$(dmcli eRT getv Device.DeviceInfo.X_COMCAST-COM_CM_MAC  | grep "value:" | awk '{ print $5 }' | tr -d ' ' )
	
	#Calculate Return Value
	if [ -n  "$cmMAC" ] ; then
		retVal=$(/usr/sbin/icontrolkey -m $cmMAC -p $param2 )
	fi
fi

#Cleanup
param2=""
cmMAC=""

if [ -e  /tmp/xhs/cyavtfjzx.pse ] ; then
	/bin/rm -rf /tmp/xhs/cyavtfjzx.pse
fi

echo $retVal
