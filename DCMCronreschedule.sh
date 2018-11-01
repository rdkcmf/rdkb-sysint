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
#

. /etc/include.properties
. /etc/device.properties


# Enable override only for non prod builds
if [ "$BUILD_TYPE" != "prod" ] && [ -f $PERSISTENT_PATH/dcm.properties ]; then
      . $PERSISTENT_PATH/dcm.properties
else
      . /etc/dcm.properties
fi

if [ -f /lib/rdk/utils.sh ]; then 
   . /lib/rdk/utils.sh
fi

export PATH=$PATH:/usr/bin:/bin:/usr/local/bin:/sbin:/usr/local/lighttpd/sbin:/usr/local/sbin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib:/lib

if [ -z $LOG_PATH ]; then
    LOG_PATH="$PERSISTENT_PATH/logs"
fi

if [ -z $PERSISTENT_PATH ]; then
    PERSISTENT_PATH="/tmp"
fi

DCM_LOG_FILE="$LOG_PATH/dcmscript.log"
TELEMETRY_INOTIFY_FOLDER="/telemetry"
TELEMETRY_INOTIFY_EVENT="$TELEMETRY_INOTIFY_FOLDER/eventType.cmd"

echo "`date` Starting execution of DCMCronreshedule.sh" >> $DCM_LOG_FILE
PEER_COMM_ID="/tmp/elxrretyt.swr"

IDLE_TIMEOUT=30

if [ "x$DCA_MULTI_CORE_SUPPORTED" == "xyes" ]; then
    echo "Signal atom to pick the update_cronschedule data for schedule telemetry !!! " >> $DCM_LOG_FILE

    ## Trigger an inotify event on ATOM
    if [ ! -f /usr/bin/GetConfigFile ];then
        echo "Error: GetConfigFile Not Found"
        exit 127
    fi

    GetConfigFile $PEER_COMM_ID
    ssh -I $IDLE_TIMEOUT -i $PEER_COMM_ID root@$ATOM_INTERFACE_IP "/bin/echo 'update_cronschedule' > $TELEMETRY_INOTIFY_EVENT" > /dev/null 2>&1
    rm -f $PEER_COMM_ID
else
    sh /lib/rdk/dca_utility.sh 3 &
fi
