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
##################################################################
## Script to execute after RFC response is processed
## Author: 
##################################################################

. /etc/include.properties

if [ -z $LOG_PATH ]; then
    LOG_PATH="/rdklogs/logs"
fi

if [ -z $RDK_PATH ]; then
    RDK_PATH="/lib/rdk"
fi
echo "RFC POSTPROCESSING IS RUN NOW !!!" >> $LOG_PATH/dcmrfc.log

#Check for lock file to prevent multiple instances of rfc_refresh.sh
if [ ! -f /tmp/.rfcLock ] ; then
   ls /tmp/RFC/.RFC_* | grep -i sshwhitelist > /dev/null
   sshFileCheck=$?
   if [ $sshFileCheck -eq 0 ] ; then
      RFC_SSH_FILE="$(ls /tmp/RFC/.RFC_* | grep -i sshwhitelist)"
      if [ -s $RFC_SSH_FILE ] ; then
         echo "RFC File for SSH present. Refreshing Firewall" >> $LOG_PATH/dcmrfc.log
         sh $RDK_PATH/rfc_refresh.sh SSH_REFRESH &
      else
         echo "RFC File for SSH is not present or empty" >> $LOG_PATH/dcmrfc.log
      fi
   fi
else
   echo "/tmp/.rfcLock file present" >> $LOG_PATH/dcmrfc.log
fi

echo "=================`date -u`=================" >> $LOG_PATH/samhain.log
[ -x /lib/rdk/samhain_starter.sh ] && /lib/rdk/samhain_starter.sh >> $LOG_PATH/samhain.log

