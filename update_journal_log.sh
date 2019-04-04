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
#update dmesg log into rdklogs/logs/messages.txt


if [ -f /etc/device.properties ]
then
    source /etc/device.properties
fi

source /etc/utopia/service.d/log_env_var.sh

current_time=0
lastync_time=0
BootupLog_is_updated=0

while [ 1 ]
do
   current_time=$(date +%s)
   if [ -f "$lastdmesgsync" ];then
   	lastsync_time=`cat $lastdmesgsync`
   fi
   
   difference_time=$(( current_time - lastsync_time ))
   lastsync_time=$current_time
   echo "$current_time" > $lastdmesgsync
   
   #Keeps appending to the existing file 
   nice -n 19 journalctl -k --since "${difference_time} sec ago" >> ${DMESG_FILE}
   if [ "$BOX_TYPE" = "XB6" -a "$MODEL_NUM" = "TG3482G" ] || [ "$BOX_TYPE" = "XF3" ];then
	   #ARRISXB6-7973: Complete journalctl logs to /rdklogs/logs/atom_journal_logs.txt.0
           uptime_in_secs="`awk '{print $1}' /proc/uptime | cut -d '.' -f1`"
           if [ $uptime_in_secs -ge 240 ]  && [ $BootupLog_is_updated -eq 0 ]; then
                nice -n 19 journalctl > ${atom_journal_log}
                BootupLog_is_updated=1;
           fi
   fi
   # ARRISXB6-8252   sleep for 60 sec until we populate journalctl
   if [ "$BOX_TYPE" = "XB6" ] && [ "$MODEL_NUM" = "TG3482G" ];then
     dmesgsyncinterval=60
   else
     dmesgsyncinterval=`syscfg get dmesglogsync_interval`
   fi
     sleep $dmesgsyncinterval 
 
done;
