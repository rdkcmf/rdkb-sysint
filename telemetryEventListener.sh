#!/bin/sh
#
# ============================================================================
# RDK MANAGEMENT, LLC CONFIDENTIAL AND PROPRIETARY
# ============================================================================
# This file (and its contents) are the intellectual property of RDK Management, LLC.
# It may not be used, copied, distributed or otherwise  disclosed in whole or in
# part without the express written permission of RDK Management, LLC.
# ============================================================================
# Copyright (c) 2014 RDK Management, LLC. All rights reserved.
# ============================================================================
#

. /etc/include.properties
. /etc/device.properties

RTL_LOG_FILE="$LOG_PATH/dcmscript.log"
TELEMETRY_INOTIFY_FOLDER=/telemetry
TELEMETRY_INOTIFY_EVENT="$TELEMETRY_INOTIFY_FOLDER/eventType.cmd"

eventType=""

if [ -f $TELEMETRY_INOTIFY_EVENT ]; then
   eventType=`cat $TELEMETRY_INOTIFY_EVENT`
else
   echo "Unkown Telemetry Event !!! Exiting" >> $RTL_LOG_FILE
   exit 0
fi

echo "`date` Telemetry Event is $eventType ..." >> $RTL_LOG_FILE

case "$eventType" in
  *splunkUpload* )
    sh /lib/rdk/dcaSplunkUpload.sh &
    ;;
  *xconf_update* )
    sh /lib/rdk/dca_utility.sh 1 &
    ;;
  *execTelemetry* )
    sh /lib/rdk/dca_utility.sh 0 &
    ;;
esac

# Clean up even listeners to receive further events
sleep 2
rm -f $TELEMETRY_INOTIFY_EVENT
