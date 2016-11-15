#!/bin/sh


source /etc/utopia/service.d/log_env_var.sh
source /etc/utopia/service.d/log_capture_path.sh
source $RDK_LOGGER_PATH/utils.sh
source $RDK_LOGGER_PATH/logfiles.sh


# We will keep max line size as 2 so that we will not lose any log message


#---------------------------------
# Initialize Variables
#---------------------------------
# URL
#URL="http://ccpxcb-dt-a001-d-1.dt.ccp.cable.comcast.com:8080/xconf/logUploadManagement/getSettings/?"
#URL="http://ssr.ccp.xcal.tv/cgi-bin/S3.cgi"
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
    verStr=`cat /fss/gw/version.txt | grep ^imagename= | cut -d "=" -f 2`
    echo $verStr
}

## Identifies whether it is a VBN or PROD build
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
		logserver=`cat $RDK_LOGGER_PATH/dcmlogservers.txt | grep $1 | cut -f2 -d"|"`
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

		if [ $totalLines -ge $MAXLINESIZE ]
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
backupenable=`syscfg get logbackup_enable`
isNvram2Supported="no"
if [ -f /etc/device.properties ]
then
   isNvram2Supported=`cat /etc/device.properties | grep NVRAM2_SUPPORTED | cut -f2 -d=`
	
fi

if [ "$isNvram2Supported" = "yes" ] && [ "$backupenable" = "true" ]
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
			while [ $loop -eq 1 ]
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

bootup_upload()
{
	if [ -e "$UPLOAD_ON_REBOOT" ]
	then
	   curDir=`pwd`

		if [ "$LOGBACKUP_ENABLE" == "true" ]; then
		if [ ! -d $LOG_SYNC_BACK_UP_REBOOT_PATH ]
		then
		    mkdir $LOG_SYNC_BACK_UP_REBOOT_PATH
		fi
			cd $LOG_SYNC_BACK_UP_REBOOT_PATH
		else
	   		cd $LOG_BACK_UP_REBOOT
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
	   
	   while [ $loop -eq 1 ]
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
		if [ $bootup_time_sec -ge 600 ] ; then
			echo_t "Boot time is more than 10 min, Breaking Loop"
			break
		fi
	   done
	   sleep 120

	   #RDKB-7196: Randomize log upload within 30 minutes
	   # We will not remove 2 minute sleep above as removing that may again result in synchronization issues with xconf

	   if [ "$fileToUpload" != "" ]
	   then
		random_sleep
	      $RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "true"
	   else 
	      echo_t "No log file found in logbackupreboot folder"
	   fi
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
	if [ "$UploadFile" != "" ]
	then
	   echo_t "File to be uploaded from logbackup/ is $UploadFile "
		if [ "$UPLOADED_AFTER_REBOOT" == "true" ]
		then
			random_sleep		
			$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false" 
		else
			while [ $loop -eq 1 ]
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
				if [ $bootup_time_sec -ge 600 ] ; then
					echo_t "Boot time is more than 10 min, Breaking Loop"
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
}	


#---------------------------------
#        Main App
#---------------------------------

get_logbackup_cfg

if [ "$LOGBACKUP_ENABLE" == "true" ]; then		
	file_list=`ls $LOG_SYNC_PATH | grep -v tgz`
	if [ "$file_list" != "" ]; then
	 	echo_t "RDK_LOGGER: creating tar from nvram2 on reboot"

		#ARRISXB6-2821:
		#DOCSIS_TIME_SYNC_NEEDED=yes for devices where DOCSIS and RDKB are in different processors and time sync needed before logbackup.
		#Checking TimeSync-status before doing backupnvram2logs_on_reboot to ensure uploaded tgz file having correct timestamp.
		#Will use default time if time not synchronized even after 2 mini of bootup to unblock other rdkbLogMonitor.sh functionality

		DOCSIS_TIME_SYNC_NEEDED=`cat /etc/device.properties | grep DOCSIS_TIME_SYNC_NEEDED | cut -f2 -d=`
		if [ "$DOCSIS_TIME_SYNC_NEEDED" == "yes" ]; then
			loop=1
			retry=1
			while [ "$loop" -eq "1" ]
			do
				echo_t "Waiting for time synchronization between processors before logbackup"
				TIME_SYNC_STATUS=`sysevent get TimeSync-status`
				if [ "$TIME_SYNC_STATUS" == "synced" ]
				then
					echo_t "Time synced. Breaking loop"
					break
				elif [ "$retry" -eq "12" ]
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
	fi
	corefile=`ls $LOG_SYNC_PATH | grep core`
	if [ "$corefile" != "" ]
	then
		rm -rf $LOG_SYNC_PATH*core*
	fi
fi

bootup_upload &

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


while [ $loop -eq 1 ]
do
	    if [ "$DeviceUP" -eq 0 ]; then
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

	    	if [ $totalSize -ge $MAXSIZE ]; then
			get_logbackup_cfg
			if [ "$LOGBACKUP_ENABLE" == "true" ]; then	
                                createSysDescr
				syncLogs_nvram2	
				backupnvram2logs "$LOG_SYNC_BACK_UP_PATH"
			else
				syncLogs
				backupAllLogs "$LOG_PATH" "$LOG_BACK_UP_PATH" "cp"
			fi	
			
			$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false"
	    	fi
	    fi

	# Syncing logs after perticular interval
	get_logbackup_cfg
	if [ "$LOGBACKUP_ENABLE" == "true" ]; then # nvram2 supported and backup is true
		minute_count=$((minute_count + 1))
		bootup_time_sec=`cat /proc/uptime | cut -d'.' -f1`
		if [ $bootup_time_sec -le 2400 ] && [ $minute_count -eq 10 ]; then
			minute_count=0
			echo_t "RDK_LOGGER: Syncing every 10 minutes for initial 30 minutes"
			syncLogs_nvram2
		elif [ $minute_count -ge $LOGBACKUP_INTERVAL ]; then
			minute_count=0
			syncLogs_nvram2
			if [ $ATOM_SYNC == "" ]; then
			   syncLogs
			fi
		fi
	else
		# Suppress ls errors to prevent constant prints in non supported devices
		file_list=`ls 2>/dev/null $LOG_SYNC_PATH`
		if [ "$file_list" != "" ]; then
			echo_t "RDK_LOGGER: Disabling nvram2 logging"
                        createSysDescr
			syncLogs_nvram2
			if [ $ATOM_SYNC == "" ]; then
				syncLogs
			fi
			backupnvram2logs "$LOG_SYNC_BACK_UP_PATH"
			$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false" "true"
		fi
	fi
              	
done

