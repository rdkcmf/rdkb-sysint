#!/bin/sh

source /etc/utopia/service.d/log_env_var.sh
source /etc/utopia/service.d/log_capture_path.sh

source $RDK_LOGGER_PATH/logfiles.sh
source $RDK_LOGGER_PATH/utils.sh

PING_PATH="/usr/sbin"
MAC=`getMacAddressOnly`
dt=`date "+%m-%d-%y-%I-%M%p"`
LOG_FILE=$MAC"_Logs_$dt.tgz"
needReboot="true"

nvram2Backup="false"
backupenabled=`syscfg get logbackup_enable`
nvram2Supported="no"
if [ -f /etc/device.properties ]
then
   nvram2Supported=`cat /etc/device.properties | grep NVRAM2_SUPPORTED | cut -f2 -d=`
fi

if [ "$nvram2Supported" = "yes" ] && [ "$backupenabled" = "true" ]
then
   nvram2Backup="true"
else
   nvram2Backup="false"
fi


getTFTPServer()
{
        if [ "$1" != "" ]
        then
		logserver=`cat $RDK_LOGGER_PATH/dcmlogservers.txt | grep $1 | cut -f2 -d"|"`
		echo $logserver
	fi
}

getBuildType()
{
   IMAGENAME=`cat /fss/gw/version.txt | grep ^imagename= | cut -d "=" -f 2`
   TEMPDEV=`echo $IMAGENAME | grep DEV`
   if [ "$TEMPDEV" != "" ]
   then
       echo "DEV"
   fi
 
   TEMPVBN=`echo $IMAGENAME | grep VBN`
   if [ "$TEMPVBN" != "" ]
   then
       echo "VBN"
   fi

   TEMPPROD=`echo $IMAGENAME | grep PROD`
   if [ "$TEMPPROD" != "" ]
   then
       echo "PROD"
   fi
   
   TEMPCQA=`echo $IMAGENAME | grep CQA`
   if [ "$TEMPCQA" != "" ]
   then
       echo "CQA"
   fi
   
}


BUILD_TYPE=`getBuildType`
SERVER=`getTFTPServer $BUILD_TYPE`

backupLogsonReboot()
{
	curDir=`pwd`
	if [ ! -d "$LOG_BACK_UP_REBOOT" ]
	then
	    mkdir $LOG_BACK_UP_REBOOT
	fi

	rm -rf $LOG_BACK_UP_REBOOT*
	
	cd $LOG_BACK_UP_REBOOT
	mkdir $dt

	# Put system descriptor string in log file
	createSysDescr

	cd $LOG_PATH
	FILES=`ls`

	for fname in $FILES
	do
		# Copy all log files from the log directory to non-volatile memory
		cp $fname $LOG_BACK_UP_REBOOT$dt ; >$fname;

	done



    # No need of checking whether file exists. Move everything

    #ret=`allFileExists $LOG_PATH`
	
	#if [ "$ret" = "yes" ]
	#then
	    #moveFiles $LOG_PATH $LOG_BACK_UP_REBOOT$dt
	#    moveFiles $LOGTEMPPATH $LOG_BACK_UP_REBOOT$dt
	#elif [ "$ret" = "no" ]
	#then

	#	for fname in $LOG_FILES_NAMES
	#	do
	#	    	if [ -f "$LOGTEMPPATH$fname" ] ; then moveFile $LOGTEMPPATH$fname $LOG_BACK_UP_REBOOT$dt; fi
	#	done

	#fi
	cd $LOG_BACK_UP_REBOOT
	cp /fss/gw/version.txt $LOG_BACK_UP_REBOOT$dt

	if [ "$atom_sync" = "yes" ]
	then
		echo_t "Check whether ATOM ip accessible before syncing ATOM side logs"
		if [ -f $PING_PATH/ping_peer ]
		then

   		        PING_RES=`ping_peer`
			CHECK_PING_RES=`echo $PING_RES | grep "packet loss" | cut -d"," -f3 | cut -d"%" -f1`

			if [ "$CHECK_PING_RES" != "" ]
			then
				if [ "$CHECK_PING_RES" -ne 100 ] 
				then
					echo_t "Ping to ATOM ip success, syncing ATOM side logs"					
				        nice -n 20 rsync root@$ATOM_IP:$ATOM_LOG_PATH$ATOM_FILE_LIST $LOG_BACK_UP_REBOOT$dt/
				else
					echo_t "Ping to ATOM ip falied, not syncing ATOM side logs"
				fi
			else
				echo_t "Ping to ATOM ip falied, not syncing ATOM side logs"
			fi
		fi

	fi

	tar -cvzf $MAC"_Logs_$dt.tgz" $dt
	echo_t "Created backup of all logs..."
	rm -rf $dt	
 	ls

	# ARRISXB3-2544 :
	# It takes too long for the unit to reboot after TFTP is completed.
	# Hence we can upload the logs once the unit boots up. We will flag it before reboot.
	touch $UPLOAD_ON_REBOOT
	#$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "TFTP" "URL" "true"
	cd $curDir
   
}

backupLogsonReboot_nvram2()
{
	curDir=`pwd`
	if [ ! -d "$LOG_SYNC_BACK_UP_REBOOT_PATH" ]; then
	    mkdir $LOG_SYNC_BACK_UP_REBOOT_PATH
	fi

	#rm -rf $LOG_SYNC_BACK_UP_REBOOT_PATH*

	# Put system descriptor string in log file
	createSysDescr

	syncLogs_nvram2

	cd $LOG_PATH
	FILES=`ls`

	for fname in $FILES
	do
		>$fname;
	done

	cd $LOG_SYNC_BACK_UP_REBOOT_PATH
        if [ -f "/version.txt" ]
        then
           cp /version.txt $LOG_SYNC_PATH
        else
	   cp /fss/gw/version.txt $LOG_SYNC_PATH
        fi
	tar -cvzf $MAC"_Logs_$dt.tgz" $LOG_SYNC_PATH
	echo_t "Created backup of all logs..."
 	ls
	rm -rf $LOG_SYNC_PATH*.txt*
	rm -rf $LOG_SYNC_PATH*.log
	touch $UPLOAD_ON_REBOOT
	cd $curDir
}

if [ "$2" = "l2sd0" ]
then
	if [ "$nvram2Backup" == "true" ]; then	
        createSysDescr
		syncLogs_nvram2	
		backupnvram2logs "$LOG_SYNC_BACK_UP_PATH"
	else
	    syncLogs
		backupAllLogs "$LOG_PATH" "$LOG_BACK_UP_PATH" "cp"
	fi

    $RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false" 
    return 0
else
  Crashed_Process_Is=$2
fi
#Call function to upload log files on reboot
if [ -e $HAVECRASH ]
then
    if [ "$Crashed_Process_Is" != "" ]
    then
	    echo_t "RDKB_REBOOT : Rebooting due to $Crashed_Process_Is PROCESS_CRASH"
    fi

    rm -f $HAVECRASH
fi

if [ "$3" == "wan-stopped" ] || [ "$3" == "Atom_Max_Log_Size_Reached" ] || [ "$2" == "DS_MANAGER_HIGH_CPU" ]
then
	echo_t "Taking log back up"
	if [ "$nvram2Backup" == "true" ]; then	
        createSysDescr

		syncLogs_nvram2	
		backupnvram2logs "$LOG_SYNC_BACK_UP_PATH"
	else
	    syncLogs
		backupAllLogs "$LOG_PATH" "$LOG_BACK_UP_PATH" "cp"
	fi
else
	if [ "$nvram2Backup" == "true" ]; then	
		backupLogsonReboot_nvram2
	else
		backupLogsonReboot
	fi	
fi
#sleep 3

if [ "$1" != "" ]
then
     needReboot=$1
fi

if [ "$needReboot" = "true" ]
then
	rebootFunc
fi

