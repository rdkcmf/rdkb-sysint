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

if [ -f /etc/include.properties ]; then
    . /etc/include.properties
fi

echo "Script called to remove the ATOM side log file contents"

LOG_FOLDER="/rdklogs/logs/"
TELEMETRY_PATH="$PERSISTENT_PATH/.telemetry"
TELEMETRY_PATH_TEMP="$TELEMETRY_PATH/tmp"

cd $LOG_FOLDER

	file_list=`ls $LOG_PATH`
	for file in $file_list
	do
		> $file
	done

# Safe clean up
# To avoid duplicate markers with random race around conditions during logupload 
if [ -d $TELEMETRY_PATH_TEMP ]; then
    echo "`date` Recovery clean up of dca seek values from flush logs"
    rm -rf $TELEMETRY_PATH_TEMP
fi 
