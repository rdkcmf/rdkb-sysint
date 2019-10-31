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

RDK_LOGGER_PATH="/rdklogger"
boot_up_log_synced="false"

#source /etc/utopia/service.d/log_env_var.sh
#source /etc/utopia/service.d/log_capture_path.sh
source $RDK_LOGGER_PATH/utils.sh
source $RDK_LOGGER_PATH/logfiles.sh

if [ -f /nvram/logupload.properties -a $BUILD_TYPE != "prod" ];then
    . /nvram/logupload.properties
fi
# We will keep max line size as 2 so that we will not lose any log message


#---------------------------------
# Initialize Variables
#---------------------------------
# As per ARRISXB3-3149


# File to save curl response 
FILENAME="$PERSISTENT_PATH/DCMresponse.txt"
# File to save http code
HTTP_CODE="$PERSISTENT_PATH/http_code"
rm -rf $HTTP_CODE
# Timeout value
timeout=10
# http header
HTTP_HEADERS='Content-Type: application/json'

## RETRY DELAY in secs
RETRY_DELAY=60
## RETRY COUNT
RETRY_COUNT=3
#default_IP=$DEFAULT_IP
upload_protocol='HTTP'
upload_httplink='None'

LOGBACKUP_ENABLE='false'
LOGBACKUP_INTERVAL=30

loop=1

minute_count=0
#tmp disable the flag now 
#UPLOAD_ON_REBOOT="/nvram/uploadonreboot"

#For rdkb-4260
SW_UPGRADE_REBOOT="/nvram/reboot_due_to_sw_upgrade"

#echo "Build Type is: $BUILD_TYPE"
#echo "SERVER is: $SERVER"
DeviceUP=0
# ARRISXB3-2544 :
# Check if upload on reboot flag is ON. If "yes", then we will upload the 
# log files first before starting monitoring of logs.

#---------------------------------
# Function declarations
#---------------------------------

## FW version from version.txt 
getFWVersion()
{
    verStr=`grep ^imagename= /fss/gw/version.txt | cut -d "=" -f 2`
    echo $verStr
}

## Identifies whether it is a VBN or PROD build
getBuildType()
{
   IMAGENAME=`sed -n 's/imagename[:|=]//p' /fss/gw/version.txt`
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

random_sleep()
{

	   randomizedNumber=`awk -v min=0 -v max=30 -v seed="$(date +%N)" 'BEGIN{srand(seed);print int(min+rand()*(max-min+1))}'`
	   RANDOM_SLEEP=`expr $randomizedNumber \\* 60`
	   echo_t "Random sleep for $RANDOM_SLEEP"
	   sleep $RANDOM_SLEEP
}

## Process the responce and update it in a file DCMSettings.conf
processJsonResponse()
{   
    if [ -f "$FILENAME" ]
    then
        OUTFILE='/tmp/DCMSettings.conf'
        sed -i 's/,"urn:/\n"urn:/g' $FILENAME # Updating the file by replacing all ',"urn:' with '\n"urn:'
        sed -i 's/{//g' $FILENAME    # Deleting all '{' from the file 
        sed -i 's/}//g' $FILENAME    # Deleting all '}' from the file
        echo "" >> $FILENAME         # Adding a new line to the file 

        #rm -f $OUTFILE #delete old file
        cat /dev/null > $OUTFILE #empty old file

        while read line
        do  
            
            # Parse the settings  by
            # 1) Replace the '":' with '='
            # 2) Delete all '"' from the value 
            # 3) Updating the result in a output file
            echo "$line" | sed 's/":/=/g' | sed 's/"//g' >> $OUTFILE 
            #echo "$line" | sed 's/":/=/g' | sed 's/"//g' | sed 's,\\/,/,g' >> $OUTFILE
            sleep 1
        done < $FILENAME
        
        rm -rf $FILENAME #Delete the /opt/DCMresponse.txt
    else
        echo "$FILENAME not found." >> $LOG_PATH/dcmscript.log
        return 1
    fi
}

totalSize=0
getLogfileSize()
{
	curDir=`pwd`
	#cd $LOG_PATH
#	cd $LOGTEMPPATH
	cd $1
	FILES=`ls`
	tempSize=0
	totalSize=0

        if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then

		totalSize=`du -c | tail -1 | awk '{print $1}'`
        else

		for f in $FILES
		do
			tempSize=`wc -c $f | cut -f1 -d" "`
			totalSize=`expr $totalSize + $tempSize`
		done
	fi

        cd $curDir
}

getTFTPServer()
{
        if [ "$1" != "" ]
        then
        logserver=`grep $1 $RDK_LOGGER_PATH/dcmlogservers.txt | cut -f2 -d"|"`
		echo $logserver
	fi
}

getLineSizeandRotate()
{
 	curDir=`pwd`
	cd $LOG_PATH

	FILES=`ls`
	tempSize=0
	totalLines=0

	for f in $FILES
	do
        	totalLines=`wc -l $f | cut -f1 -d" "`

		if [ "$totalLines" -ge "$MAXLINESIZE" ]
		then
        		rotateLogs $f
			totalLines=0
		fi
	done
	cd $curDir
}

reset_offset()
{
	# Suppress ls errors to prevent constant prints in non supported devices
	file_list=`ls 2>/dev/null $LOG_SYNC_PATH`

	for file in $file_list
	do
		echo "1" > $LOG_SYNC_PATH$file # Setting Offset as 1 and clearing the file
	done

}

BUILD_TYPE=`getBuildType`
SERVER=`getTFTPServer $BUILD_TYPE`

get_logbackup_cfg()
{
default_logbackup_enable="true"
backupenable=`syscfg get logbackup_enable`
backupenable_err=`echo $backupenable | grep "error" -i`
if [ "$backupenable_err" != "" ]
then
	backupenable=$default_logbackup_enable
fi

#isNvram2Supported="no"
#if [ -f /etc/device.properties ]
#then
#   isNvram2Supported=`cat /etc/device.properties | grep NVRAM2_SUPPORTED | cut -f2 -d=`
#	
#fi

if [ "$NVRAM2_SUPPORTED" = "yes" ] && [ "$backupenable" = "true" ]
then
	LOGBACKUP_ENABLE="true"
else
	LOGBACKUP_ENABLE="false"
fi
	LOGBACKUP_INTERVAL=`syscfg get logbackup_interval`

}

upload_nvram2_logs()
{
	curDir=`pwd`

	cd $LOG_SYNC_BACK_UP_PATH

	UploadFile=`ls | grep "tgz"`
	if [ "$UploadFile" != "" ]
	then
	   echo_t "File to be uploaded from is $UploadFile "
		if [ "$UPLOADED_AFTER_REBOOT" == "true" ]
		then
			$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false"
		else
			while [ "$loop" = "1" ]
			do
		    	     echo_t "Waiting for stack to come up completely to upload logs..."
		      	     sleep 30
			     WEBSERVER_STARTED=`sysevent get webserver`
		 	     if [ "$WEBSERVER_STARTED" == "started" ]
			     then
				echo_t "Webserver $WEBSERVER_STARTED..., uploading logs after 2 mins"
				break
			    fi
			done
			sleep 120
			random_sleep
			$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false"
			UPLOADED_AFTER_REBOOT="true"
		fi
	fi

	cd $curDir

	echo_t "uploading over from nvram2 "
}

bootup_remove_old_backupfiles()
{
	if [ "$LOGBACKUP_ENABLE" == "true" ]; then
		#Check whether $LOG_BACK_UP_REBOOT directory present or not
		if [ -d "$LOG_BACK_UP_REBOOT" ]; then
			cd $LOG_BACK_UP_REBOOT
			filesPresent=`ls $LOG_BACK_UP_REBOOT | grep -v tgz`
			
			#To remove not deleted old nvram/logbackupreboot/ files  
			if [ "$filesPresent" != "" ]
			then
				echo "Removing old files from $LOG_BACK_UP_REBOOT path during reboot..."
				rm -rf $LOG_BACK_UP_REBOOT*.log*
				rm -rf $LOG_BACK_UP_REBOOT*.txt*
				rm -rf $LOG_BACK_UP_REBOOT*core*
			fi 
			
			cd -
		fi
	fi
}

bootup_tarlogs()
{
	#dt may be epoc time at the time of sourceing.So defining again here.
	dt=`date "+%m-%d-%y-%I-%M%p"`
	echo_t "RDK_LOGGER: bootup_tarlogs"

	#Remove old backup log files	
	bootup_remove_old_backupfiles

	if [ -e "$UPLOAD_ON_REBOOT" ]
	then
	        curDir=`pwd`

		if [ "$LOGBACKUP_ENABLE" == "true" ]; then
		    if [ ! -d $LOG_SYNC_BACK_UP_REBOOT_PATH ]
		    then
		        mkdir $LOG_SYNC_BACK_UP_REBOOT_PATH
		    fi
			cd $LOG_SYNC_BACK_UP_REBOOT_PATH
                        filesPresent=`ls $LOG_SYNC_BACK_UP_REBOOT_PATH | grep -v tgz`
		else
	   		cd $LOG_BACK_UP_REBOOT
                        filesPresent=`ls $LOG_BACK_UP_REBOOT | grep -v tgz`
		fi

            if [ "$filesPresent" != "" ]
            then
               
               # Print sys descriptor value if bootup is not after software upgrade.
               # During software upgrade, we print this value before reboot.
               # This is done to reduce user triggered reboot time 
               if [ ! -f "/nvram/reboot_due_to_sw_upgrade" ]
               then
                   echo "Create sysdescriptor before creating tar ball after reboot.."
                   createSysDescr >> $ARM_LOGS_NVRAM2
               fi 
		
		rm -rf *.tgz
               echo "*.tgz" > $PATTERN_FILE # .tgz should be excluded while tar
               if [ -f /tmp/backup_onboardlogs ] && [ -f /nvram/.device_onboarded ]; then
                echo "tar activation logs from bootup_tarlogs"
                copy_onboardlogs "$LOG_SYNC_PATH"
                tar -X $PATTERN_FILE -cvzf ${MAC}_Logs_${dt}_activation_log.tgz $LOG_SYNC_PATH
                rm -rf /tmp/backup_onboardlogs
               else
                echo "tar logs from bootup_tarlogs"
                tar -X $PATTERN_FILE -cvzf ${MAC}_Logs_${dt}.tgz $LOG_SYNC_PATH
               fi
               rm $PATTERN_FILE
               rm -rf $LOG_SYNC_PATH*.txt*
	       rm -rf $LOG_SYNC_PATH*.log*
	       rm -rf $LOG_SYNC_PATH*core*
	       rm -rf $LOG_SYNC_PATH$PcdLogFile
	       rm -rf $LOG_SYNC_PATH$RAM_OOPS_FILE
	       echo_t "RDK_LOGGER: tar activation logs from bootup_tarlogs ${MAC}_Logs_${dt}.tgz"
            fi
	fi
}	

bootup_upload()
{

	echo_t "RDK_LOGGER: bootup_upload"

	if [ -e "$UPLOAD_ON_REBOOT" ]
	then

            if [ "$LOGBACKUP_ENABLE" == "true" ]; then
               #Sync log files immediately after reboot
               echo_t "RDK_LOGGER: Sync logs to nvram2 after reboot"
               syncLogs_nvram2
            else
               BACKUPENABLE=`syscfg get logbackup_enable`
               if [ "$BACKUPENABLE" = "true" ]; then
                  # First time call syncLogs after boot,
                  #  remove existing log files (in $LOG_FILES_NAMES) in $LOG_BACK_UP_REBOOT
                  curDir=`pwd`
                  cd $LOG_BACK_UP_REBOOT
                  for fileName in $LOG_FILES_NAMES
                  do
                     rm 2>/dev/null $fileName #avoid error message
                  done
                  cd $curDir
                  syncLogs
               fi
            fi

	   macOnly=`getMacAddressOnly`
	   fileToUpload=`ls | grep tgz`
	   # This check is to handle migration scenario from /nvram to /nvram2
	   if [ "$fileToUpload" = "" ] && [ "$LOGBACKUP_ENABLE" = "true" ]
	   then
	       echo_t "Checking if any file available in $LOG_BACK_UP_REBOOT"
	       fileToUpload=`ls $LOG_BACK_UP_REBOOT | grep tgz`
	   fi
	       
	   echo_t "File to be uploaded is $fileToUpload ...."

	   HAS_WAN_IP=""
	   
	   while [ "$loop" = "1" ]
	   do
	      echo_t "Waiting for stack to come up completely to upload logs..."
	      sleep 30
	      WEBSERVER_STARTED=`sysevent get webserver`
	      if [ "$WEBSERVER_STARTED" == "started" ]
	      then
		   echo_t "Webserver $WEBSERVER_STARTED..., uploading logs after 2 mins"
		   break
	      fi

		bootup_time_sec=`cat /proc/uptime | cut -d'.' -f1`
		if [ "$bootup_time_sec" -ge "600" ] ; then
			echo_t "Boot time is more than 10 min, Breaking Loop"
			break
		fi
	   done
	   sleep 120

	   if [ "$fileToUpload" = "" ] && [ "$LOGBACKUP_ENABLE" = "true" ]
	   then
	       echo_t "Checking if any file available in $TMP_LOG_UPLOAD_PATH"
	       fileToUpload=`ls $TMP_LOG_UPLOAD_PATH | grep tgz`

	   fi

	   echo_t "File to be uploaded is $fileToUpload ...."
	   #RDKB-7196: Randomize log upload within 30 minutes
	   # We will not remove 2 minute sleep above as removing that may again result in synchronization issues with xconf
		boot_up_log_synced="true"
	   if [ "$fileToUpload" != "" ]
	   then
	   	
            random_sleep
	      $RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "true" "" $TMP_LOG_UPLOAD_PATH
	   else 
	      echo_t "No log file found in logbackupreboot folder"
	   fi
	   
        #Venu
	logBackupEnable=`syscfg get log_backup_enable` 
        if [ "$logBackupEnable" = "true" ];then
          if [ -d $PRESERVE_LOG_PATH ] ; then
            cd $PRESERVE_LOG_PATH
            fileToUpload=`ls | grep tgz`
            if [ "$fileToUpload" != "" ]
            then
              sleep 60
              echo_t "Uploading backup logs found in $PRESERVE_LOG_PATH"
              $RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "true" "" $PRESERVE_LOG_PATH
            else 
             echo_t "No backup logs found in $PRESERVE_LOG_PATH"
            fi
          fi #end if [ -d $PRESERVE_LOG_PATH 
        fi #end if [ "$logBackupEnable" = "true" ]
        
	   UPLOADED_AFTER_REBOOT="true"
	   sleep 2
	   rm $UPLOAD_ON_REBOOT
	   cd $curDir
	fi

	echo_t "Check if any tar file available in /logbackup/ "
	curDir=`pwd`

        if [ "$LOGBACKUP_ENABLE" == "true" ]; then
            cd $LOG_SYNC_BACK_UP_PATH
        else
            cd $LOG_BACK_UP_PATH
        fi

	UploadFile=`ls | grep "tgz"`

	if [ "$UploadFile" = "" ] && [ "$LOGBACKUP_ENABLE" = "true" ]
	then
		echo_t "Checking if any file available in $TMP_LOG_UPLOAD_PATH"
		UploadFile=`ls $TMP_LOG_UPLOAD_PATH | grep tgz`
	fi

	echo_t "File to be uploaded is $UploadFile ...."

	if [ "$UploadFile" != "" ]
	then
	        echo_t "File to be uploaded from logbackup/ is $UploadFile "
		if [ "$UPLOADED_AFTER_REBOOT" == "true" ]
		then
			random_sleep		
			$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false" "" $TMP_LOG_UPLOAD_PATH
		else
			while [ "$loop" = "1" ]
			do
		    	     echo_t "Waiting for stack to come up completely to upload logs..."
		      	     sleep 30
			     WEBSERVER_STARTED=`sysevent get webserver`
		 	     if [ "$WEBSERVER_STARTED" == "started" ]
			     then
				echo_t "Webserver $WEBSERVER_STARTED..., uploading logs after 2 mins"
				break
			     fi

                             bootup_time_sec=`cat /proc/uptime | cut -d'.' -f1`
                             if [ "$bootup_time_sec" -ge "600" ] ; then
                                  echo_t "Boot time is more than 10 min, Breaking Loop"
                                  break
                             fi
			done
			sleep 120
			random_sleep
			$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false" "" $TMP_LOG_UPLOAD_PATH
			UPLOADED_AFTER_REBOOT="true"
		fi
	fi

	cd $curDir
}	

#ARRISXB6-5184 : Remove hidden files coming up in /rdklogs/logs and /nvram/logs
remove_hidden_files()
{
    if [ -d "$1" ] ; then
        cd $1
        HIDDEN_FILES=`ls -A | grep "^\." | xargs echo -n`
        if [ "$HIDDEN_FILES" != "" ] ; then
            echo "Removing following hidden files in `pwd` : $HIDDEN_FILES"
            rm -f $HIDDEN_FILES
        fi
        cd - >/dev/null
    fi
}


#---------------------------------
#        Main App
#---------------------------------
# "remove_old_logbackup" if to remove old logbackup from logbackupreboot directory
triggerType=$1
echo_t "rdkbLogMonitor: Trigger type is $triggerType"

get_logbackup_cfg

if [ "$triggerType" == "remove_old_logbackup" ]; then	
	echo "Remove old log backup files"
	bootup_remove_old_backupfiles
	exit
fi

########################################################
#               RDKB-26588 && TRDKB-355 - Mitigation   #
#         To Ensure only one instance is running       #
########################################################
RDKLOG_LOCK_DIR="/tmp/locking_logmonitor"

if mkdir $RDKLOG_LOCK_DIR
then
    echo "Got the first instance running"
else
    echo "Already a instance is running; No 2nd instance"
    exit
fi
########################################################

PEER_COMM_ID="/tmp/elxrretyt-logm.swr"

RebootReason=`syscfg get X_RDKCENTRAL-COM_LastRebootReason`

if [ "$BOX_TYPE" = "XB3" ]; then
        if [ "$RebootReason" = "RESET_ORIGIN_ATOM_WATCHDOG" ] || [ "$RebootReason" = "RESET_ORIGIN_ATOM" ]; then
	       GetConfigFile $PEER_COMM_ID
	       scp -i $PEER_COMM_ID -r root@$ATOM_INTERFACE_IP:$RAM_OOPS_FILE_LOCATION$RAM_OOPS_FILE  $LOG_SYNC_PATH > /dev/null 2>&1
	       rm -rf $PEER_COMM_ID
	fi
        if [ "$RebootReason" = "HOST-OOPS-REBOOT" ]; then
	       cp $RAM_OOPS_FILE_LOCATION$RAM_OOPS_FILE0  $LOG_SYNC_PATH$RAM_OOPS_FILE0_HOST
	       cp $RAM_OOPS_FILE_LOCATION$RAM_OOPS_FILE1  $LOG_SYNC_PATH$RAM_OOPS_FILE1_HOST
        fi
fi

if [ "$LOGBACKUP_ENABLE" == "true" ]; then		

	#ARRISXB6-3045 - This is speific to Axb6. If nvram2 supported hardware found, all syncing should switch to nvram2/logs.
	#While switching from nvram to nvram2, old logs should be backed-up, uploaded and cleared from old sync path.
#	model=`cat /etc/device.properties | grep MODEL_NUM  | cut -f2 -d=`
	if [ "$BOX_TYPE" = "XB6" -a "$MANUFACTURE" = "Arris" ];then
		isNvram2Mounted=`grep nvram2 /proc/mounts`
		if [ -d "/nvram2" ];then
			if [ "$isNvram2Mounted" != "" ];then
				if [ -d "/nvram/logs" ];then
					file_list=`ls /nvram/logs/`
					if [ "$file_list" != "" ]; then
						echo_t "nvram/logs contains older logs"
						if [ ! -d "$LOG_SYNC_PATH" ];then
							echo_t "Creating new sync path - nvram2/logs"
							mkdir $LOG_SYNC_PATH
						fi
						echo_t "nvram2 detected first time. Copying nvram/logs to nvram2/logs for boottime logupload"
						cp /nvram/logs/* "$LOG_SYNC_PATH"
					fi
					echo_t "logs copied to nvram2. Removing old log path - nvram/logs"
					rm -rf "/nvram/logs"
				fi
			else
			echo_t "nvram2 available, but not mounted."
			fi
		fi
	fi

	PCIE_REBOOT_INDICATOR="/nvram/pcie_error_reboot_occurred"
	PCIE_REBOOT_LOG="/rdklogs/logs/pcie_reboot.txt"

	if [ -f $PCIE_REBOOT_INDICATOR ]
	then
		echo "Previous Reboot reason:PCIE ENUM failed" > $PCIE_REBOOT_LOG
		cat "$PCIE_REBOOT_INDICATOR" >> $PCIE_REBOOT_LOG
		rm $PCIE_REBOOT_INDICATOR
		if [ -f /nvram/pcie_error_reboot_needed ];then
			rm /nvram/pcie_error_reboot_needed
		fi
        if [ -f /nvram/pcie_error_reboot_counter ];then
            rm /nvram/pcie_error_reboot_counter
        fi
	fi
	
	#ARRISXB6-2821:
        #DOCSIS_TIME_SYNC_NEEDED=yes for devices where DOCSIS and RDKB are in different processors 
        #and time sync needed before logbackup.
        #Checking TimeSync-status before doing backupnvram2logs_on_reboot to ensure uploaded tgz file 
        #having correct timestamp.
        #Will use default time if time not synchronized even after 2 mini of bootup to unblock 
        #other rdkbLogMonitor.sh functionality

	#TCCBR-4723 To handle all log upload with epoc time cases. Brought this block of code just 
	#above to the prevoius condition for making all cases to wait for timesync before log upload.

        if [ "$DOCSIS_TIME_SYNC_NEEDED" == "yes" ]; then
		if [ "`sysevent get TimeSync-status`" != "synced" ];then
			loop=1
                        retry=1
                        while [ "$loop" = "1" ]
                        do
                                echo_t "Waiting for time synchronization between processors before logbackup"
                                TIME_SYNC_STATUS=`sysevent get TimeSync-status`
                                if [ "$TIME_SYNC_STATUS" == "synced" ]
                                then
                                        echo_t "Time synced. Breaking loop"
                                        break
                                elif [ "$retry" = "12" ]
                                then
                                        echo_t "Time not synced even after 2 min retry. Breaking loop and using default time for logbackup"
                                        break
                                else
                                        echo_t "Time not synced yet. Sleeping.. Retry:$retry"
                                        retry=`expr $retry + 1`
                                        sleep 10
                                fi
                        done
		fi
        fi
	#TCCBR-4275 to handle factory reset case.
	if ( [ "$file_list" != "" ] && [ ! -f "$UPLOAD_ON_REBOOT" ] ) || ( [ "$RebootReason" == "factory-reset" ] ); then
	 	echo_t "RDK_LOGGER: creating tar from nvram2 on reboot"

		#HUB4 uses NTP for syncing time. It doesnt have DOCSIS time sync, Hence waiting for NTP time sync.
		if [ "$BOX_TYPE" == "HUB4" ]; then
			loop=1
			retry=1
			while [ "$loop" = "1" ]
			do
				echo_t "Waiting for time synchronization before logbackup"
				TIME_SYNC_STATUS=`timedatectl status | grep "NTP synchronized" | cut -d " " -f 3`
				if [ "$TIME_SYNC_STATUS" == "yes" ]
				then
					echo_t "Time synced. Breaking loop"
					break
				elif [ "$retry" = "12" ]
				then
					echo_t "Time not synced even after 2 min retry. Breaking loop and using default time for logbackup"
					break
				else
					echo_t "Time not synced yet. Sleeping.. Retry:$retry"
					retry=`expr $retry + 1`
					sleep 10
				fi
			done
		fi

		backupnvram2logs_on_reboot "$LOG_SYNC_BACK_UP_PATH"
		#upload_nvram2_logs

                if [ "$LOGBACKUP_ENABLE" == "true" ]; then
                   #Sync log files immediately after reboot
                   echo_t "RDK_LOGGER: Sync logs to nvram2 after reboot"
                   syncLogs_nvram2
                else
                   BACKUPENABLE=`syscfg get logbackup_enable`
                   if [ "$BACKUPENABLE" = "true" ]; then
                       # First time call syncLogs after boot,
                       #  remove existing log files (in $LOG_FILES_NAMES) in $LOG_BACK_UP_REBOOT
                       curDir=`pwd`
                       cd $LOG_BACK_UP_REBOOT
                       for fileName in $LOG_FILES_NAMES
                       do
                          rm 2>/dev/null $fileName #avoid error message
                       done
                       cd $curDir
                       syncLogs
                   fi
                fi
	elif [ "$file_list" == "" ] && [ ! -f "$UPLOAD_ON_REBOOT" ]; then
		if [ "$LOGBACKUP_ENABLE" == "true" ]; then
			#Sync log files immediately after reboot
			echo_t "RDK_LOGGER: Sync logs to nvram2 after reboot"
			syncLogs_nvram2
		fi
	fi
fi

# rdkb-24823 create tar file, then do upload in the background,
bootup_tarlogs
bootup_upload &

UPLOAD_LOGS=`processDCMResponse`
while [ "$loop" = "1" ]
do

	    if [ "$DeviceUP" = "0" ]; then
	        #for rdkb-4260
	        if [ -f "$SW_UPGRADE_REBOOT" ]; then
	           echo_t "RDKB_REBOOT: Device is up after reboot due to software upgrade"
	           #deleting reboot_due_to_sw_upgrade file
	           echo_t "Deleting file /nvram/reboot_due_to_sw_upgrade"
	           rm -rf /nvram/reboot_due_to_sw_upgrade
	           DeviceUP=1
	        else
	           echo_t "RDKB_REBOOT: Device is up after reboot"
	           DeviceUP=1
	        fi
	    fi

	    sleep 60
	    
	    if [ ! -e $REGULAR_UPLOAD ]
	    then
		getLogfileSize "$LOG_PATH"

	        if [ "$totalSize" -ge "$MAXSIZE" ]; then
			get_logbackup_cfg

			if [ "$UPLOAD_LOGS" = "" ] || [ ! -f "$DCM_SETTINGS_PARSED" ]
			then
				echo_t "processDCMResponse to get the logUploadSettings"
				UPLOAD_LOGS=`processDCMResponse`
			fi  
    
			echo_t "UPLOAD_LOGS val is $UPLOAD_LOGS"
			if [ "$UPLOAD_LOGS" = "true" ] || [ "$UPLOAD_LOGS" = "" ]
			then
				UPLOAD_LOGS="true"
				# this file is touched to indicate log upload is enabled
				# we check this file in logfiles.sh before creating tar ball.
				# tar ball will be created only if this file exists.
				echo_t "Log upload is enabled. Touching indicator in regular upload"         
				touch /tmp/.uploadregularlogs
			else
				echo_t "Log upload is disabled. Removing indicator in regular upload"         
				rm -rf /tmp/.uploadregularlogs                                
			fi
			
			cd $LOG_SYNC_BACK_UP_REBOOT_PATH
			FILE_NAME=`ls | grep "tgz"`
			# This event is set to "yes" whenever wan goes down. 
			# So, we should not move tar to /tmp in that case.
			wan_event=`sysevent get wan_event_log_upload`
			wan_status=`sysevent get wan-status`
			if [ "$FILE_NAME" != "" ] && [ "$boot_up_log_synced" = "false" ]; then
				mkdir $TMP_LOG_UPLOAD_PATH
				mv $FILE_NAME $TMP_LOG_UPLOAD_PATH
			fi
			cd -
			boot_up_log_synced="true"
			if [ "$LOGBACKUP_ENABLE" == "true" ]; then	
				createSysDescr
				syncLogs_nvram2

                                # Check if there is any tar ball to be preserved
                                # else tar ball will be removed in backupnvram2logs
                                logBackupEnable=`syscfg get log_backup_enable`
                                if [ "$logBackupEnable" = "true" ];then
                                   echo_t "Back up to preserve location is enabled"
                                   fileName=`ls -tr $LOG_SYNC_BACK_UP_PATH | grep tgz | head -n 1`
                                   if [ "$fileName" != "" ]
                                   then
                                      # Call PreserveLog which will move logs to preserve location
                                      preserveThisLog $fileName $LOG_SYNC_BACK_UP_PATH
                                   fi
                                fi 	

				backupnvram2logs "$LOG_SYNC_BACK_UP_PATH"
			else
				syncLogs
				backupAllLogs "$LOG_PATH" "$LOG_BACK_UP_PATH" "cp"
			fi
	
		        if [ "$UPLOAD_LOGS" = "true" ] 
			then	
				$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false"
			else
				echo_t "Regular log upload is disabled"         
			fi
	    	fi
	    fi
	    
	    # We do not want to upload anything if log upload is disabled in DCM
            # If log upload is enabled, then try uploading logs from preserved location if file exists.
	    if [ ! -e $REGULAR_UPLOAD ] && [ "$UPLOAD_LOGS" = "true" ] 
	    then
         
	       logBackupEnable=`syscfg get log_backup_enable`
               if [ "$logBackupEnable" = "true" ];then
                  if [ -d $PRESERVE_LOG_PATH ] ; then
                     cd $PRESERVE_LOG_PATH
                     fileToUpload=`ls | grep tgz`
                     if [ "$fileToUpload" != "" ]
                     then
                        echo_t "Uploading backup logs found in $PRESERVE_LOG_PATH"
                        $RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "true" "" $PRESERVE_LOG_PATH
                     fi
                  fi #end if [ -d $PRESERVE_LOG_PATH 
               fi #end if [ "$logBackupEnable" = "true" ]
	    fi #if [ ! -e $REGULAR_UPLOAD ]
	    
	# Syncing logs after particular interval
	get_logbackup_cfg
	if [ "$LOGBACKUP_ENABLE" == "true" ]; then # nvram2 supported and backup is true
		minute_count=$((minute_count + 1))
		bootup_time_sec=`cat /proc/uptime | cut -d'.' -f1`
		if [ "$bootup_time_sec" -le "2400" ] && [ $minute_count -eq 10 ]; then
			minute_count=0
			echo_t "RDK_LOGGER: Syncing every 10 minutes for initial 30 minutes"
			syncLogs_nvram2
		elif [ "$minute_count" -ge "$LOGBACKUP_INTERVAL" ]; then
			minute_count=0
			syncLogs_nvram2
			if [ "$ATOM_SYNC" == "" ]; then
			   syncLogs
			fi
			#ARRISXB6-5184
			if [ "$BOX_TYPE" = "XB6" -a "$MANUFACTURE" = "Arris" ] ; then
			    remove_hidden_files "/rdklogs/logs"
			    remove_hidden_files "/nvram/logs"
			    remove_hidden_files "/nvram2/logs"
			fi
		fi
	else
		# Suppress ls errors to prevent constant prints in non supported devices
		file_list=`ls 2>/dev/null $LOG_SYNC_PATH`
		if [ "$file_list" != "" ]; then
			echo_t "RDK_LOGGER: Disabling nvram2 logging"
			createSysDescr
                        
			if [ "$UPLOAD_LOGS" = "" ] || [ ! -f "$DCM_SETTINGS_PARSED" ]
			then
				echo_t "processDCMResponse to get the logUploadSettings"
				UPLOAD_LOGS=`processDCMResponse`
			fi  
    
			echo_t "UPLOAD_LOGS val is $UPLOAD_LOGS"
			if [ "$UPLOAD_LOGS" = "true" ] || [ "$UPLOAD_LOGS" = "" ]		
			then
				UPLOAD_LOGS="true"
				echo_t "Log upload is enabled. Touching indicator in maintenance window"         
				touch /tmp/.uploadregularlogs
			else
				echo_t "Log upload is disabled. Removing indicator in maintenance window"         
				rm /tmp/.uploadregularlogs
			fi

			syncLogs_nvram2
			if [ "$ATOM_SYNC" == "" ]; then
				syncLogs
			fi
			backupnvram2logs "$LOG_SYNC_BACK_UP_PATH"

		        if [ "$UPLOAD_LOGS" = "true" ]
			then			
				$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false" "true"
			else
				echo_t "Regular log upload is disabled"         
			fi

		fi
	fi
              	
done

########################################################
#               RDKB-26588 && TRDKB-355 - Mitigation   #
#         To Ensure only one instance is running       #
########################################################
rm -rf $RDKLOG_LOCK_DIR
########################################################

