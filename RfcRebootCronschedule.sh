#! /bin/sh

source /etc/log_timestamp.sh

CRONTAB_DIR="/var/spool/cron/crontabs/"
CRONTAB_FILE=$CRONTAB_DIR"root"
CRONFILE_BK="/tmp/cron_tab$$.txt"
LOG_FILE="/rdklogs/logs/dcmrfc.log"
FW_START="/nvram/.FirmwareUpgradeStartTime"
FW_END="/nvram/.FirmwareUpgradeEndTime"
RFC_REBOOT_SCHEDULED="/tmp/.RfcwaitingReboot"

if [ -f /etc/device.properties ]
then
    source /etc/device.properties
fi

calcRebootExecTime()
{

        # Extract maintenance window start and end time
        if [ -f "$FW_START" ] && [ -f "$FW_END" ]
        then
           start_time=`cat $FW_START`
           end_time=`cat $FW_END`
        else
           start_time=3600
           end_time=14400
        fi

        #if start_time and end_time are set it to default
        if [ "$start_time" = "$end_time" ]
        then
                echo_t "[RfcRebootCronschedule.sh] start_time and end_time are equal.so,setting them to default" >> $LOG_FILE
                start_time=3600
                end_time=14400
        fi

        #Get local time off set
        time_offset=`dmcli eRT getv Device.Time.TimeOffset | grep "value:" | cut -d ":" -f 3 | tr -d ' '`


        #Maintence start and end time in local
        main_start_time=$((start_time-time_offset))
        main_end_time=$((end_time-time_offset))

        #calculate random time in sec
        rand_time_in_sec=`awk -v min=$main_start_time -v max=$main_end_time -v seed="$(date +%N)" 'BEGIN{srand(seed);print int(min+rand()*(max-min+1))}'`

        # To avoid cron to be set beyond 24 hr clock limit
        if [ $rand_time_in_sec -ge 86400 ]
        then
                rand_time_in_sec=$((rand_time_in_sec-86400))
                echo_t "[RfcRebootCronschedule.sh] Random time in sec exceed 24 hr limit.setting it correct limit" >> $LOG_FILE

        fi

        #conversion of random generated time to HH:MM:SS format
                #calculate random second
                rand_time=$rand_time_in_sec
                rand_sec=$((rand_time%60))

                #calculate random minute
                rand_time=$((rand_time/60))
                rand_min=$((rand_time%60))

                #calculate random hour
                rand_time=$((rand_time/60))
                rand_hr=$((rand_time%60))

        echo_t "[RfcRebootCronschedule.sh]start_time: $start_time, end_time: $end_time" >> $LOG_FILE
        echo_t "[RfcRebootCronschedule.sh]time_offset: $time_offset" >> $LOG_FILE
        echo_t "[RfcRebootCronschedule.sh]main_start_time: $main_start_time , main_end_time= $main_end_time" >> $LOG_FILE
        echo_t "[RfcRebootCronschedule.sh]rand_time_in_sec: $rand_time_in_sec ,rand_hr: $rand_hr ,rand_min: $rand_min ,rand_sec: $rand_sec" >> $LOG_FILE

}

ScheduleCron()
{
        # Dump existing cron jobs to a file & add new job
        crontab -l -c $CRONTAB_DIR > $CRONFILE_BK
        echo "$rand_min $rand_hr * * * /etc/RFC_Reboot.sh" >> $CRONFILE_BK
        crontab $CRONFILE_BK -c $CRONTAB_DIR
        rm -rf $CRONFILE_BK
        touch $RFC_REBOOT_SCHEDULED


}

#calculate ane schedule cron job

calcRebootExecTime
if [ -f $CRONTAB_FILE ]
then
	 ScheduleCron
	 echo_t "[RfcRebootCronschedule.sh] RFC Reboot cron job scheduled" >> $LOG_FILE
fi
