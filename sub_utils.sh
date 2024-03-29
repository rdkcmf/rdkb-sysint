#!/bin/sh
##########################################################################
# If not stated otherwise in this file or this component's Licenses.txt
# file the following copyright and licenses apply:
#
# Copyright 2021 RDK Management
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

counter=0

if [ -f $RDK_PATH/utils.sh ]; then
   . $RDK_PATH/utils.sh
fi

## Get Mac address without colon
getMacAddressWithoutColon()
{
     if [ $BOX_TYPE = "XF3" ]; then

         while [ ! -f /tmp/epon_agent_initialized ] && [ $counter -lt 10 ]
         do
              sleep 1
              counter=$((counter+1))
         done

     fi

     mac=$(getMacAddress)

     sync
     temp=`echo $mac | sed 's/://g' | awk '{print tolower($0)}'`

     if [ $BOX_TYPE != "XB3" ]; then

         /bin/systemctl set-environment MAC_ADDR="$temp"

     fi

     echo $temp
}

getMacAddressWithoutColon
