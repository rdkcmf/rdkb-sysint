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
source /lib/rdk/getpartnerid.sh

retVal=""

if [ ! -f /usr/bin/GetConfigFile ];then
    echo "Error: GetConfigFile Not Found"
    exit 127
fi

#partnerId=$(getPartnerId)
if [ "$BOX_TYPE" = "XB6" -a "$MANUFACTURE" = "Arris" ]; then
    #Use nvm cust_id instead of getPartnerId to avoid syscfg dependency
    cust_idx=`arris_rpc_client arm nvm_get cust_id`
fi

#Retrieve Parameter2
mkdir -p /tmp/xhs
if [ "$cust_idx" = "cox" ];then
    COMMID="/tmp/xhs/cyavtfjzx.pse-cox"
else
    COMMID="/tmp/xhs/cyavtfjzx.pse"
fi

GetConfigFile $COMMID
param2=`/bin/cat $COMMID`

if [ -n  "$param2" ] ; then

    if [ "$BOX_TYPE" = "XB6" -a "$MANUFACTURE" = "Arris" ]; then
        #Retrieve CM MAC-Use RPC instead of DMCLI because of Reset to Defaults and timing.
        cmMAC=$(arris_rpc_client arm nvm_get cm_mac)
    fi

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
