#! /bin/sh

source /etc/log_timestamp.sh

CRONTAB_DIR="/var/spool/cron/crontabs/"
CRONTAB_FILE=$CRONTAB_DIR"root"
CRONFILE_BK="/tmp/cron_tab$$.txt"
LOG_FILE="/rdklogs/logs/dcmrfc.log"
RFC_REBOOT_SCHEDULED="/tmp/.RfcwaitingReboot"
DCM_CONF="/tmp/DCMSettings.conf"

. /etc/device.properties

calcRebootExecTime()
{

    cron=''
    if [ -f $DCM_CONF ]; then
        cron=`cat $DCM_CONF | grep 'urn:settings:CheckSchedule:cron' | cut -d '=' -f2`
    else
        if [ -f $PERSISTENT_PATH/tmpDCMSettings.conf ]; then
            cron=`grep 'urn:settings:CheckSchedule:cron' $PERSISTENT_PATH/tmpDCMSettings.conf | cut -d '=' -f2`
        fi
    fi

    # Scheduling the job 15 mins ahead of scheduling FWDnld
    if [ -n "$cron" ]; then
        vc1=`echo "$cron" | awk '{print $1}'`
        vc2=`echo "$cron" | awk '{print $2}'`
        vc3=`echo "$cron" | awk '{print $3}'`
        vc4=`echo "$cron" | awk '{print $4}'`
        vc5=`echo "$cron" | awk '{print $5}'`
        if [ $vc1 -gt 44 ]; then
            # vc1 = vc1 + 15 - 60
            vc1=`expr $vc1 - 45`
            vc2=`expr $vc2 + 1`
            if  [ $vc2 -eq 24 ]; then
                vc2=0
            fi
        else
            vc1=`expr $vc1 + 15`
        fi
        cron=''
        cron=`echo "$vc1 $vc2 $vc3 $vc4 $vc5"`
    fi
}

ScheduleCron()
{
        # Dump existing cron jobs to a file & add new job
        crontab -l -c $CRONTAB_DIR > $CRONFILE_BK
        echo "$cron /etc/RFC_Reboot.sh" >> $CRONFILE_BK
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
