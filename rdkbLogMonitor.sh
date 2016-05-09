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
	cd $LOG_PATH
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


#---------------------------------
#        Main App
#---------------------------------
loop=1
BUILD_TYPE=`getBuildType`
SERVER=`getTFTPServer $BUILD_TYPE`

#tmp disable the flag now 
#UPLOAD_ON_REBOOT="/nvram/uploadonreboot"

#For rdkb-4260
SW_UPGRADE_REBOOT="/nvram/reboot_due_to_sw_upgrade"

#echo "Build Type is: $BUILD_TYPE"
#echo "SERVER is: $SERVER"
DeviceUP=0
# ARRISXB3-2544 :
# Check if upload on reboo tflag is ON. If "yes", then we will upload the 
# log files first before starting monitoring of logs.
if [ -e "$UPLOAD_ON_REBOOT" ]
then
   curDir=`pwd`
   cd $LOG_BACK_UP_REBOOT
   macOnly=`getMacAddressOnly`
   fileToUpload=`ls | grep $macOnly`
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
   $RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "true"
   sleep 2
   rm $UPLOAD_ON_REBOOT
   cd $curDir
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

	    	getLogfileSize

	    	if [ $totalSize -ge $MAXSIZE ]
	    	then
			#backupAllLogs "$LOG_PATH" "$LOG_BACK_UP_PATH" "cp"
   			backupAllLogs "$LOG_PATH" "$LOG_BACK_UP_PATH" "cp"

			$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false"
	    	fi
	    fi
#   fi
		
              	
done

