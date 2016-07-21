#!/bin/sh


source /fss/gw/etc/utopia/service.d/log_env_var.sh
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
	#echo ">>>>>>>>>>>>>>>>>>> reset offset <<<<<<<<<<<<<<<<<<<<"
	file_list=`ls $LOG_SYNC_PATH`

	for file in $file_list
	do
		echo "1" > $LOG_SYNC_PATH$file # Setting Offset as 1 and clearing the file
	done

}

get_logbackup_cfg()
{
	#echo ">>>>>>>>>>>>>>>>>>> get logbackup cfg <<<<<<<<<<<<<<<<<<<<"
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

	#echo ">>>>>>>>>>>>>>>>>>> LOGBACKUP_ENABLE = $LOGBACKUP_ENABLE"
	#echo ">>>>>>>>>>>>>>>>>>> LOGBACKUP_INTERVAL = $LOGBACKUP_INTERVAL"

}

upload_nvram2_logs()
{
	echo ">>>>>>>>>>>>>>>>>>> Check if files available in nvram2 "
	curDir=`pwd`

	cd $LOG_SYNC_BACK_UP_PATH

	UploadFile=`ls | grep "tgz"`
	if [ "$UploadFile" != "" ]
	then
	   echo "File to be uploaded from is $UploadFile "
		if [ "$UPLOADED_AFTER_REBOOT" == "true" ]
		then
			$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false"
		else
			while [ $loop -eq 1 ]
			do
		    	     echo "Waiting for stack to come up completely to upload logs..."
		      	     sleep 30
			     WEBSERVER_STARTED=`sysevent get webserver`
		 	     if [ "$WEBSERVER_STARTED" == "started" ]
			     then
				echo "Webserver $WEBSERVER_STARTED..., uploading logs after 2 mins"
				break
			    fi
			done
			sleep 120
			$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false"
			UPLOADED_AFTER_REBOOT="true"
		fi
	fi

	cd $curDir

	echo ">>>>>>>>>>>>>>>>>>> uploading over from nvram2 "
}


#---------------------------------
#        Main App
#---------------------------------
loop=1
BUILD_TYPE=`getBuildType`
SERVER=`getTFTPServer $BUILD_TYPE`

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

get_logbackup_cfg

if [ -e "$UPLOAD_ON_REBOOT" ]
then
   curDir=`pwd`

	if [ "$LOGBACKUP_ENABLE" == "true" ]; then
		cd $LOG_SYNC_BACK_UP_REBOOT_PATH
	else
   		cd $LOG_BACK_UP_REBOOT
	fi

   macOnly=`getMacAddressOnly`
   fileToUpload=`ls | grep tgz`
   # This check is to handle migration scenario from /nvram to /nvram2
   if [ "$fileToUpload" = "" ] && [ "$LOGBACKUP_ENABLE" = "true" ]
   then
       echo "Checking if any file available in $LOG_BACK_UP_REBOOT"
       fileToUpload=`ls $LOG_BACK_UP_REBOOT | grep tgz`
   fi
       
   echo "File to be uploaded is $fileToUpload ...."

   HAS_WAN_IP=""
   
   while [ $loop -eq 1 ]
   do
      echo "Waiting for stack to come up completely to upload logs..."
      sleep 30
      WEBSERVER_STARTED=`sysevent get webserver`
      if [ "$WEBSERVER_STARTED" == "started" ]
      then
           echo "Webserver $WEBSERVER_STARTED..., uploading logs after 2 mins"
           break
      fi
   done
   sleep 120

   if [ "$fileToUpload" != "" ]
   then
      $RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "true"
   else 
      echo "No log file found in logbackupreboot folder"
   fi
   UPLOADED_AFTER_REBOOT="true"
   sleep 2
   rm $UPLOAD_ON_REBOOT
   cd $curDir
fi

echo "Check if any tar file available in /logbackup/ "
curDir=`pwd`

	if [ "$LOGBACKUP_ENABLE" == "true" ]; then
		cd $LOG_SYNC_BACK_UP_PATH
	else
   		cd $LOG_BACK_UP_PATH
	fi

UploadFile=`ls | grep "tgz"`
if [ "$UploadFile" != "" ]
then
   echo "File to be uploaded from logbackup/ is $UploadFile "
	if [ "$UPLOADED_AFTER_REBOOT" == "true" ]
	then
		$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false" 
	else
	        while [ $loop -eq 1 ]
	        do
	    	     echo "Waiting for stack to come up completely to upload logs..."
	      	     sleep 30
	             WEBSERVER_STARTED=`sysevent get webserver`
         	     if [ "$WEBSERVER_STARTED" == "started" ]
	             then
		        echo "Webserver $WEBSERVER_STARTED..., uploading logs after 2 mins"
		        break
	            fi
	        done
	        sleep 120
		$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false"
		UPLOADED_AFTER_REBOOT="true"
	fi
fi

cd $curDir

if [ "$LOGBACKUP_ENABLE" == "true" ]; then		
	file_list=`ls $LOG_SYNC_PATH`
	if [ "$file_list" != "" ]; then
	 	echo ">>>>>>>>>>>>>>>>>>> Uploading logs from nvram2 on reboot"
		backupnvram2logs_on_reboot "$LOG_SYNC_BACK_UP_PATH"
		upload_nvram2_logs
	fi
fi	

while [ $loop -eq 1 ]
do
#    wanIp=`getIPAddress`
#    if [ ! $wanIp ] ;then
            #echo "waiting for IP ..."
#            sleep 15
#    else
	
		#cp /fss/gw/version.txt /var/tmp/logs/
		if [ "$DeviceUP" -eq 0 ]; then
			#for rdkb-4260
			if [ -f "$SW_UPGRADE_REBOOT" ]; then
				echo "RDKB_REBOOT: Device is up after reboot due to software upgrade"
				#deleting reboot_due_to_sw_upgrade file
				echo "Deleting file /nvram/reboot_due_to_sw_upgrade"
				rm -rf /nvram/reboot_due_to_sw_upgrade
				DeviceUP=1
			else
				echo "RDKB_REBOOT: Device is up after reboot"
				DeviceUP=1
			fi
		fi

	    sleep 60
	    
	    if [ ! -e $REGULAR_UPLOAD ]
	    then
		
	#	if [ ! -d "$LOGTEMPPATH" ]
	#	then
		#	mkdir -p $LOGTEMPPATH
					
	#	fi

	#	if [ ! -e $LOG_FILE_FLAG ]
	#	then
	#		createFiles
	#	fi

		#getLineSizeandRotate	

	    	getLogfileSize "$LOG_PATH"

	    	if [ $totalSize -ge $MAXSIZE ]; then
			get_logbackup_cfg
			if [ "$LOGBACKUP_ENABLE" == "true" ]; then	
				#echo ">>>>>>>>>>>>>>>>>>> >1.5 backup case <<<<<<<<<<<<<<<<<<<<"		
				syncLogs_nvram2	
				backupnvram2logs "$LOG_SYNC_BACK_UP_PATH"
			else
				backupAllLogs "$LOG_PATH" "$LOG_BACK_UP_PATH" "cp"
			fi	
			
			$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false"
	    	fi
	    fi
#   fi
	# Syncing logs after perticular interval
	get_logbackup_cfg
	if [ "$LOGBACKUP_ENABLE" == "true" ]; then
		#echo ">>>>>>>>>>>>>>>>>>> backup enable <<<<<<<<<<<<<<<<<<<<"
		minute_count=$((minute_count + 1))
		if [ $minute_count -ge $LOGBACKUP_INTERVAL ]; then
			#echo ">>>>>>>>>>>>>>>>>>> normal backup case <<<<<<<<<<<<<<<<<<<<"
			minute_count=0
			syncLogs_nvram2
		fi
	else
		file_list=`ls $LOG_SYNC_PATH`
		if [ "$file_list" != "" ]; then
			echo ">>>>>>>>>>>>>>>>>>> disabling nvram2 logging <<<<<<<<<<<<<<<<<<<<"
			syncLogs_nvram2
			backupnvram2logs "$LOG_SYNC_BACK_UP_PATH"
			$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false" "true"
		fi
	fi
              	
done

