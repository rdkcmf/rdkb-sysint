#!/bin/sh

source /etc/device.properties

loop=1
LOG_PATH=/rdklogs/logs/

if [ "$UI_IN_ATOM" = "true" ]
then
   FILES="AtomConsolelog.txt.0 CRlog.txt.0 lighttpderror.log WiFilog.txt.0"
else
   FILES="AtomConsolelog.txt.0 CRlog.txt.0 WiFilog.txt.0"
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
