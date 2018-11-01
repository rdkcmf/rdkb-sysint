#!/bin/sh
#update dmesg log into rdklogs/logs/messages.txt


if [ -f /etc/device.properties ]
then
    source /etc/device.properties
fi

current_time=0
lastync_time=0
DMESG_FILE="/rdklogs/logs/messages.txt"
atom_journal_log="/rdklogs/logs/atom_journal_logs.txt.0"
BootupLog_is_updated=0

while [ 1 ]
do
   current_time=$(date +%s)
   difference_time=$(( current_time - lastsync_time ))
   lastsync_time=$current_time
   #Keeps appending to the existing file 
   nice -n 19 journalctl -k --since "${difference_time} sec ago" >> ${DMESG_FILE}
   if [ "$BOX_TYPE" = "XB6" ] && [ "$MODEL_NUM" = "TG3482G" ];then
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
