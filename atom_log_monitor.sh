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
source /etc/logFiles.properties
source /etc/log_timestamp.sh
loop=1
LOG_PATH=/rdklogs/logs/

#wait for components to create log
sleep 10

TMP_FILE_LIST=$(echo $ATOM_FILE_LIST | tr "," " " | tr "{" " " | tr "}" " " | tr "*" "0")
TMP_FILE_LIST=${TMP_FILE_LIST/"txt0"/"txt"}
for file in $TMP_FILE_LIST; do
  if [ ! -f $LOG_PATH$file ]; then
   touch $LOG_PATH$file
  fi
done

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

		for f in $TMP_FILE_LIST
		do
			tempSize=`du -c $f | tail -1 | awk '{print $1}'`
			totalSize=`expr $totalSize + $tempSize`
		done
        else

		for f in $TMP_FILE_LIST
		do
			tempSize=`wc -c $f | cut -f1 -d" "`
			totalSize=`expr $totalSize + $tempSize`
		done
	fi

	if [ $totalSize -ge $MAXSIZE ]; then
		echo_t "MAXSIZE reached , upload the logs"
		dmcli eRT setv Device.LogBackup.X_RDKCENTRAL-COM_SyncandUploadLogs bool true
	fi

	cd $currdir

done
