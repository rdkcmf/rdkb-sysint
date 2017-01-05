#!/bin/sh

retVal=""

#Retrieve Parameter2
if [ -s  /etc/xhs/cyavtfjzx.pse ] ; then

	mkdir -p /tmp/xhs
	/usr/bin/configparamgen jx /etc/xhs/cyavtfjzx.pse /tmp/xhs/cyavtfjzx.pse
	param2=`/bin/cat /tmp/xhs/cyavtfjzx.pse`
fi

if [ -n  "$param2" ] ; then

	#Retrieve CM MAC-Use RPC instead of DMCLI because of Reset to Defaults and timing.
	cmMAC=$(arris_rpc_client arm nvm_get cm_mac)
	
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
