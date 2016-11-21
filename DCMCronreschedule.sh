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

if [ "x$DCA_MULTI_CORE_SUPPORTED" == "xyes" ]; then
    echo "Signal atom to pick the update_cronschedule data for schedule telemetry !!! " >> $DCM_LOG_FILE
    ## Trigger an inotify event on ATOM 
    ssh root@$ATOM_INTERFACE_IP "/bin/echo 'update_cronschedule' > $TELEMETRY_INOTIFY_EVENT" > /dev/null 2>&1
else
    sh /lib/rdk/dca_utility.sh 3 &
fi
