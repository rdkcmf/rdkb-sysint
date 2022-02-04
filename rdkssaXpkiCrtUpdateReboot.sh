#! /bin/sh

source /usr/ccsp/tad/corrective_action.sh

LOG_FILE="/rdklogs/logs/rdkssa.txt"

#Setting last reboot to xpktcrtupdate_reboot
echo_t "[rdkssaXpkiCrtUpdateReboot.sh] setting last reboot to xpktcrtupdate_reboot" >> $LOG_FILE
setRebootreason xpktcrtupdate_reboot 1

#take log back up and reboot

echo_t "[rdkssaXpkiCrtUpdateReboot.sh] take log back up and reboot" >> $LOG_FILE
sh /rdklogger/backupLogs.sh true &

