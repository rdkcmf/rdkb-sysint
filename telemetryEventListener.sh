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
source /etc/log_timestamp.sh
RTL_LOG_FILE="$LOG_PATH/dcmscript.log"
TELEMETRY_INOTIFY_FOLDER=/telemetry
TELEMETRY_INOTIFY_EVENT="$TELEMETRY_INOTIFY_FOLDER/eventType.cmd"
TELEMETRY_EXEC_COMPLETE="/tmp/.dca_done"

eventType=""

cleanUp() {
    rm -f $TELEMETRY_INOTIFY_EVENT
}

trap cleanUp EXIT

if [ -f $TELEMETRY_INOTIFY_EVENT ]; then
   eventType=`cat $TELEMETRY_INOTIFY_EVENT`
else
   echo_t "Unkown Telemetry Event !!! Exiting" >> $RTL_LOG_FILE
   exit 0
fi

echo_t "Telemetry Event is $eventType ..." >> $RTL_LOG_FILE

case "$eventType" in
  *splunkUpload* )
    sh /lib/rdk/dcaSplunkUpload.sh &
    ;;
  *notifyFlushLogs* )
    touch $TELEMETRY_EXEC_COMPLETE
    sh /lib/rdk/dcaSplunkUpload.sh &
    ;;
  *xconf_update* )
    sh /lib/rdk/dca_utility.sh 1 &
    ;;
  *execTelemetry* )
    sh /lib/rdk/dca_utility.sh 2 &
    ;;
  *update_cronschedule* )
    sh /lib/rdk/dca_utility.sh 3 &
    ;;
  *bootupBackup* )
    sh /lib/rdk/dcaSplunkUpload.sh logbackup_without_upload &
    ;;
  *notifyTelemetryCleanup* )
    touch $TELEMETRY_EXEC_COMPLETE
    ;;
esac

# Clean up even listeners to receive further events
sleep 2
