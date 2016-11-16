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

source /etc/device.properties

loop=1
LOG_PATH=/rdklogs/logs/

if [ "$UI_IN_ATOM" = "true" ]
then
   FILES="AtomConsolelog.txt.0 CRlog.txt.0 lighttpderror.log WiFilog.txt.0 ap_init.txt.0 hostapd_error_log.txt XsmartLog.txt.0 TouchstoneLog.txt.0 bandsteering_periodic_status.txt bandsteering_log.txt wifihealth.txt"
else
   FILES="AtomConsolelog.txt.0 CRlog.txt.0 WiFilog.txt.0 XsmartLog.txt.0 TouchstoneLog.txt.0"
fi

while [ "$loop" -eq 1 ]
do

	sleep 60
	if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
	      MAXSIZE=512
	else
	      MAXSIZE=524288
	fi

	currdir=`pwd`
	cd $LOG_PATH
	totalSize=0
        if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then

		for f in $FILES
		do
			tempSize=`du -c $f | tail -1 | awk '{print $1}'`
			totalSize=`expr $totalSize + $tempSize`
		done
        else

		for f in $FILES
		do
			tempSize=`wc -c $f | cut -f1 -d" "`
			totalSize=`expr $totalSize + $tempSize`
		done
	fi

	if [ $totalSize -ge $MAXSIZE ]; then
		echo "MAXSIZE reached , upload the logs"
		dmcli eRT setv Device.LogBackup.X_RDKCENTRAL-COM_SyncandUploadLogs bool true
	fi

	cd $currdir

done
