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

source /etc/utopia/service.d/log_env_var.sh
source /etc/utopia/service.d/log_capture_path.sh

source $RDK_LOGGER_PATH/logfiles.sh
source $RDK_LOGGER_PATH/utils.sh

LOG_UPLOAD_PID="/tmp/.log_upload.pid"

# exit if an instance is already running
if [ ! -f $LOG_UPLOAD_PID ];then
    # store the PID
    echo $$ > $LOG_UPLOAD_PID
else
    pid=`cat $LOG_UPLOAD_PID`
    if [ -d /proc/$pid ];then
          echo_t "backupLogs.sh already running..."
          exit 0
    else
          echo $$ > $LOG_UPLOAD_PID
    fi
fi

PING_PATH="/usr/sbin"
MAC=`getMacAddressOnly`
dt=`date "+%m-%d-%y-%I-%M%p"`
LOG_FILE=$MAC"_Logs_$dt.tgz"
needReboot="true"
PATTERN_FILE="/tmp/pattern_file"

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


backup_log_pidCleanup()
{
   # PID file cleanup
   if [ -f $LOG_UPLOAD_PID ];then
        rm -rf $LOG_UPLOAD_PID
   fi
}

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
	#createSysDescr

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
	    #moveFiles $LOG_PATH $LOG_BACK_UP_REBOOT$dte
	#    moveFiles $LOGTEMPPATH $LOG_BACK_UP_REBOOT$dte
	#elif [ "$ret" = "no" ]
	#then

	#	for fname in $LOG_FILES_NAMES
	#	do
	#	    	if [ -f "$LOGTEMPPATH$fname" ] ; then moveFile $LOGTEMPPATH$fname $LOG_BACK_UP_REBOOT$dte; fi
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
					protected_rsync $LOG_BACK_UP_REBOOT$dt/
#nice -n 20 rsync root@$ATOM_IP:$ATOM_LOG_PATH$ATOM_FILE_LIST $LOG_BACK_UP_REBOOT$dt/ > /dev/null 2>&1
				else
					echo_t "Ping to ATOM ip falied, not syncing ATOM side logs"
				fi
			else
				echo_t "Ping to ATOM ip falied, not syncing ATOM side logs"
			fi
		fi

	fi
	#echo "*.tgz" > $PATTERN_FILE # .tgz should be excluded while tar
	#tar -X $PATTERN_FILE -cvzf $MAC"_Logs_$dt.tgz" $dt
	#rm $PATTERN_FILE
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

	# Put system descriptor string in log file if it is a software upgrade.
        # For non-software upgrade reboots, sysdescriptor will be printed during bootup
	if [ -f "/nvram/reboot_due_to_sw_upgrade" ]
        then
             createSysDescr
        fi 

	syncLogs_nvram2

        if [ -e $HAVECRASH ]
        then
            if [ "$atom_sync" = "yes" ]
            then
               # Remove the contents of ATOM side log files.
                echo_t "Call dca for log processing and then flush ATOM logs"
                flush_atom_logs 
            fi
            rm -rf $HAVECRASH
        fi

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
	#echo "*.tgz" > $PATTERN_FILE # .tgz should be excluded while tar
	#tar -X $PATTERN_FILE -cvzf $MAC"_Logs_$dt.tgz" $LOG_SYNC_PATH
	#rm $PATTERN_FILE
	echo_t "Created backup of all logs..."
 	ls
	#rm -rf $LOG_SYNC_PATH*.txt*
	#rm -rf $LOG_SYNC_PATH*.log
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
    backup_log_pidCleanup
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
    # We will remove the HAVECRASH flag after handling the log back up.
    #rm -f $HAVECRASH
fi

if [ "$3" == "wan-stopped" ] || [ "$3" == "Atom_Max_Log_Size_Reached" ] || [ "$2" == "DS_MANAGER_HIGH_CPU" ] || [ "$2" == "ATOM_RO" ]
then
	echo_t "Taking log back up"
	if [ "$nvram2Backup" == "true" ]; then	
                # Setting event to protect tar backup to /tmp whenever wan goes down and file size reached more than threshold
		sysevent set wan_event_log_upload yes
		createSysDescr
		syncLogs_nvram2	
		backupnvram2logs "$LOG_SYNC_BACK_UP_PATH"
                if [ "$3" = "wan-stopped" ]
                then
                   isBackupEnabled=`syscfg get log_backup_enable`
                   if [ "$isBackupEnabled" = "true" ]
                   then
                      fileName=`ls $LOG_SYNC_BACK_UP_PATH | grep tgz`
                      echo_t "Back up to preserve location is enabled"
                      # Call PreserveLog which will move logs to preserve location
                      preserveThisLog $fileName $LOG_SYNC_BACK_UP_PATH
                   else
                      echo_t "Back up to preserve location is disabled"
                   fi
                fi
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

if [ "$4" = "upload" ]
then
	/rdklogger/uploadRDKBLogs.sh "" HTTP "" false
fi

if [ "$1" != "" ]
then
     needReboot=$1
fi

backup_log_pidCleanup

if [ "$needReboot" = "true" ]
then
	rebootFunc
fi

