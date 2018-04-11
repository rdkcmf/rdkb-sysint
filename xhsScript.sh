#!/bin/sh

retVal=""

if [ ! -f /usr/bin/GetConfigFile ];then
    echo "Error: GetConfigFile Not Found"
    exit 127
fi

COMMID="/tmp/xhs/cyavtfjzx.pse"

#Retrieve Parameter2
mkdir -p /tmp/xhs
GetConfigFile $COMMID
param2=`/bin/cat $COMMID`

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

if [ -e $COMMID ] ; then
	/bin/rm -rf $COMMID
fi

echo $retVal
