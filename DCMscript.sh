#!/bin/sh
#
# ============================================================================
# RDK MANAGEMENT, LLC CONFIDENTIAL AND PROPRIETARY
# ============================================================================
# This file (and its contents) are the intellectual property of RDK Management, LLC.
# It may not be used, copied, distributed or otherwise  disclosed in whole or in
# part without the express written permission of RDK Management, LLC.
# ============================================================================
# Copyright (c) 2014 RDK Management, LLC. All rights reserved.
# ============================================================================
#

. /etc/include.properties
. /etc/device.properties


# Enable override only for non prod builds
if [ "$BUILD_TYPE" != "prod" ] && [ -f $PERSISTENT_PATH/dcm.properties ]; then
      . $PERSISTENT_PATH/dcm.properties
else
      . /etc/dcm.properties
fi

if [ -f /fss/gw/rdklogger/utils.sh  ]; then 
   . /fss/gw/rdklogger/utils.sh
fi

export PATH=$PATH:/usr/bin:/bin:/usr/local/bin:/sbin:/usr/local/lighttpd/sbin:/usr/local/sbin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib:/lib

if [ -z $LOG_PATH ]; then
    LOG_PATH="$PERSISTENT_PATH/logs"
fi

if [ -z $PERSISTENT_PATH ]; then
    PERSISTENT_PATH="/tmp"
fi

TELEMETRY_PATH="$PERSISTENT_PATH/.telemetry"
DCMFLAG="/tmp/.DCMSettingsFlag"
DCM_LOG_FILE="$LOG_PATH/dcmscript.log"
DCM_SETTINGS_CONF="/tmp/DCMSettings.conf"
# http header
HTTP_HEADERS='Content-Type: application/json'
## RETRY DELAY in secs
RETRY_DELAY=60
## RETRY COUNT
RETRY_COUNT=3

echo "`date` Starting execution of DCMscript.sh" >> $DCM_LOG_FILE

if [ $# -ne 5 ]; then
    echo "`date` Argument does not match" >> $DCM_LOG_FILE
    echo 0 > $DCMFLAG
    exit 1
fi
#---------------------------------
# Initialize Variables
#---------------------------------
URL=$2
tftp_server=$3
reboot_flag=$4
checkon_reboot=$5

echo "`date` URL: $URL" >> $DCM_LOG_FILE
echo "`date` DCM_TFTP_SERVER: $tftp_server" >> $DCM_LOG_FILE
echo "`date` BOOT_FLAG: $reboot_flag" >> $DCM_LOG_FILE
echo "`date` CHECK_ON_REBOOT: $checkon_reboot" >> $DCM_LOG_FILE

# This override doesn't happen during device bootup
if [ -f $DCM_SETTINGS_CONF ]; then
    Check_URL=`grep 'urn:settings:ConfigurationServiceURL' $DCM_SETTINGS_CONF | cut -d '=' -f2 | head -n 1`
    if [ -n "$Check_URL" ]; then
        URL=`grep 'urn:settings:ConfigurationServiceURL' $DCM_SETTINGS_CONF | cut -d '=' -f2 | sed 's/^"//' | sed 's/"$//' | head -n 1`
        #last_char=`echo $URL | sed -e 's/\(^.*\)\(.$\)/\2/'`
        last_char=`echo $URL | awk '$0=$NF' FS=`
        if [ "$last_char" != "?" ]; then
            URL="$URL?"
        fi
    fi
fi

# Start crond daemon for yocto builds
if [ -f /etc/os-release ]; then
    mkdir -p $CRON_SPOOL
    touch $CRON_SPOOL/root
    pidof crond
    if [ $? -ne 0 ]; then
        crond -l 9 
    fi
fi

# Clean up for telemetry during bootup
if [ -d $TELEMETRY_PATH ]; then
    echo "Removing Telemetry directory $TELEMETRY_PATH" >> $DCM_LOG_FILE
    rm -rf $TELEMETRY_PATH
fi

# File to save curl response 
#FILENAME="$PERSISTENT_PATH/DCMresponse.txt"
DCMRESPONSE="$PERSISTENT_PATH/DCMresponse.txt"
# File to save http code
HTTP_CODE="$PERSISTENT_PATH/http_code"
rm -rf $HTTP_CODE
# Cron job file name
current_cron_file="$PERSISTENT_PATH/cron_file.txt"
# Timeout value
timeout=10
default_IP=$DEFAULT_IP
upload_protocol='TFTP'
upload_httplink=$HTTP_UPLOAD_LINK

## Get Receiver Id
getReceiverId()
{
    if [ -f "$PERSISTENT_PATH/www/whitebox/wbdevice.dat" ]
    then
        ReceiverId=`cat $PERSISTENT_PATH/www/whitebox/wbdevice.dat`
        echo "$ReceiverId"
    else
        echo " "
    fi
}

## Get Controller Id
getControllerId()
{
    echo "2504"
}

## Get ChannelMap Id
getChannelMapId()
{
    echo "2345"
}

## Get VOD Id
getVODId()
{
    echo "15660"
}

## Process the responce and update it in a file DCMSettings.conf
## Function to remove HTML from curl response obtained from server and makes the conf file in a easy to read format
processJsonResponse()
{  
    FILENAME=$1
    #Condider getting the filename as an argument instead of using global file name 
    if [ -f "$FILENAME" ]; then
        # Start pre-processing the original file
        sed -i 's/,"urn:/\n"urn:/g' $FILENAME # Updating the file by replacing all ',"urn:' with '\n"urn:'
        sed -i 's/^{//g' $FILENAME # Delete first character from file '{'
        sed -i 's/}$//g' $FILENAME # Delete first character from file '}'
        echo "" >> $FILENAME         # Adding a new line to the file 
        # Start pre-processing the original file

        OUTFILE=$DCM_SETTINGS_CONF
	OUTFILEOPT="$PERSISTENT_PATH/.DCMSettings.conf"
        #rm -f $OUTFILE #delete old file
        cat /dev/null > $OUTFILE #empty old file
	cat /dev/null > $OUTFILEOPT

        while read line
        do 
            # Special processing for telemetry 
            profile_Check=`echo "$line" | grep -ci 'TelemetryProfile'`
            if [ $profile_Check -ne 0 ];then
                #echo "$line"
                echo "$line" | sed 's/"header":"/"header" : "/g' | sed 's/"content":"/"content" : "/g' | sed 's/"type":"/"type" : "/g' >> $OUTFILE

		echo "$line" | sed 's/"header":"/"header" : "/g' | sed 's/"content":"/"content" : "/g' | sed 's/"type":"/"type" : "/g' | sed -e 's/uploadRepository:URL.*","//g'  >> $OUTFILEOPT
            else
                echo "$line" | sed 's/":/=/g' | sed 's/"//g' >> $OUTFILE 
            fi            
        done < $FILENAME
        
        rm -rf $FILENAME #Delete the $PERSISTENT_PATH/DCMresponse.txt
    else
        echo "$FILENAME not found." >> $DCM_LOG_FILE
        return 1
    fi
}

sendHttpRequestToServer()
{
    resp=0
    FILENAME=$1
    URL=$2
    JSONSTR='estbMacAddress='$(getErouterMacAddress)'&firmwareVersion='$(getFWVersion)'&env='$(getBuildType)'&model='$(getModel)'&ecmMacAddress='$(getMacAddress)'&controllerId='$(getControllerId)'&channelMapId='$(getChannelMapId)'&vodId='$(getVODId)'&version=2'

    last_char=`echo $URL | awk '$0=$NF' FS=`
    if [ "$last_char" != "?" ]; then
        URL="$URL?"
    fi
        
    CURL_CMD="curl -w '%{http_code}\n' --interface $EROUTER_INTERFACE --connect-timeout $timeout -m $timeout -o  \"$FILENAME\" '$URL$JSONSTR'"
    echo "`date` CURL_CMD: $CURL_CMD" >> $DCM_LOG_FILE
    result= eval $CURL_CMD > $HTTP_CODE
    ret=$?
    sleep $timeout
    http_code=$(awk -F\" '{print $1}' $HTTP_CODE)
    echo "`date` ret = $ret http_code: $http_code" >> $DCM_LOG_FILE
	
    # Retry for STBs hosted in open internet
    if [ ! -z "$ENABLE_CB" -a "$ENABLE_CB"!=" " -a $http_code -eq 000 ] && [ -f /usr/bin/configparamgen ]; then
        echo "`date` Retry attempt to get logupload setting for STB in wild " >> $DCM_LOG_FILE

        SIGN_CMD="configparamgen 3 \"$JSONSTR\""
        eval $SIGN_CMD > /tmp/.signedRequest
        CB_SIGNED_REQUEST=`cat /tmp/.signedRequest`
        rm -f /tmp/.signedRequest
        CURL_CMD="curl -w '%{http_code}\n' --interface $EROUTER_INTERFACE --connect-timeout $timeout -m $timeout -o  \"$FILENAME\" \"$CB_SIGNED_REQUEST\""
        result= eval $CURL_CMD > $HTTP_CODE
        http_code=$(awk -F\" '{print $1}' $HTTP_CODE)
        ret=$?
    fi

    if [ $ret = 0 ] && [ "$http_code" = "404" ] ; then
         echo "`Timestamp` Received HTTP 404 Response from Xconf Server. Retry logic not needed" >> $DCM_LOG_FILE
	 resp=1
    elif [ $ret -ne 0 -o $http_code -ne 200 ] ; then
        echo "`date` HTTP request failed" >> $DCM_LOG_FILE
        rm -rf $DCM_SETTINGS_CONF
        resp=1
    else
        echo "`date` HTTP request success. Processing response.." >> $DCM_LOG_FILE
        # Create DCM settings conf from DCM response 
        processJsonResponse "$FILENAME"
        stat=$?
        echo "`date` processJsonResponse returned $stat" >> $DCM_LOG_FILE
        if [ $stat -ne 0 ] ; then
            echo "`date` Processing response failed." >> $DCM_LOG_FILE
            rm -rf $DCM_SETTINGS_CONF
            resp=1
        else
            resp=0
            echo 1 > $DCMFLAG
        fi
    fi
    echo "`date` resp = $resp" >> $DCM_LOG_FILE
    return $resp
}


# Safe wait for IP acquisition
# TBD this logic may be different for RDKB devices
loop=1
counter=0
while [ $loop -eq 1 ]
do
    estbIp=`getCMIPAddress`   # This needs to be changed to wait for erouter IP address
    if [ "X$estbIp" == "X" ]; then
         echo "`date` waiting for IP" >> $DCM_LOG_FILE
         sleep 10
         let counter++
         if [ "$counter" -eq 30 ] || [ "$counter" -eq 90 ]; then
             sh $RDK_PATH/dca_utility.sh 0 0
         fi
    else
         loop=0
         sh $RDK_PATH/dca_utility.sh 0 0
    fi
done

# Retry for getting a valid JSON response
loop=1
count=0
while [ $loop -eq 1 ]
do
    ret=1
    if [ "$DEVICE_TYPE" != "mediaclient" ] && [ "$estbIp" == "$default_IP" ] ; then
	  ret=0
    fi

    if [ $checkon_reboot -eq 1 ]; then
	sendHttpRequestToServer $DCMRESPONSE $URL
	ret=$?
	echo "`date` sendHttpRequestToServer returned $ret" >> $DCM_LOG_FILE
    else
	ret=0
	echo "`date` sendHttpRequestToServer has not executed since the value of 'checkon_reboot' is $checkon_reboot" >> $DCM_LOG_FILE
    fi                

    sleep 15

    if [ $ret -ne 0 ]; then
        echo "`date` Processing response failed." >> $DCM_LOG_FILE
        rm -rf $FILENAME $HTTP_CODE
        count=$((count + 1))
        if [ $count -ge $RETRY_COUNT ]; then
            echo " `date` $RETRY_COUNT tries failed. Giving up..." >> $DCM_LOG_FILE
            echo 0 > $DCMFLAG
            exit 1
        fi
        echo "`date` count = $count. Sleeping $RETRY_DELAY seconds ..." >> $LOG_PATH/dcmscript.log
        sleep $RETRY_DELAY
    else
        # 2] Initialize telemetry and schedule cron for telemetry
        loop=0
	cron=''
	scheduler_Check=`grep '"schedule":' $DCM_SETTINGS_CONF`
	if [ -n "$scheduler_Check" ]; then
	    cron=`cat $DCM_SETTINGS_CONF | grep -i TelemetryProfile | awk -F '"schedule":' '{print $NF}' | awk -F "," '{print $1}' | sed 's/://g' | sed 's/"//g' | sed -e 's/^[ ]//' | sed -e 's/^[ ]//'`
	fi

	if [ -n "$cron" ]; then
            #Get the cronjob time (minutes)
	    sleep_time=`echo "$cron" | awk -F '/' '{print $2}' | cut -d ' ' -f1`
	    if [ -n $sleep_time ];then
		sleep_time=`expr $sleep_time - 1` #Subtract 1 miute from it
		sleep_time=`expr $sleep_time \* 60` #Make it to seconds
                # Adding generic RANDOM number implementation as sh in RDK_B doesn't support RANDOM
                RANDOM=`awk -v min=5 -v max=10 'BEGIN{srand(); print int(min+rand()*(max-min+1)*(max-min+1)*1000)}'`
		sleep_time=$(($RANDOM%$sleep_time)) #Generate a random value out of it
	    else
		sleep_time=10
	    fi
	    # Dump existing cron jobs to a file
	    crontab -l -c $CRON_SPOOL > $current_cron_file
	    # Check whether any cron jobs are existing or not
	    existing_cron_check=`cat $current_cron_file | tail -n 1`
	    tempfile="$PERSISTENT_PATH/tempfile.txt"
	    rm -rf $tempfile  # Delete temp file if existing
	    if [ -n "$existing_cron_check" ]; then
		rtl_cron_check=`grep -c 'dca_utility.sh' $current_cron_file`
		if [ $rtl_cron_check -eq 0 ]; then
		    echo "$cron nice -n 20 sh $RDK_PATH/dca_utility.sh $sleep_time 1" >> $tempfile
		fi
		while read line
		do
		    retval=`echo "$line" | grep 'dca_utility.sh'`
		    if [ -n "$retval" ]; then
			echo "$cron nice -n 20 sh $RDK_PATH/dca_utility.sh $sleep_time 1" >> $tempfile
		    else
			echo "$line" >> $tempfile
		    fi
		done < $current_cron_file
	    else
		# If no cron job exists, create one, with the value from DCMSettings.conf file
		echo "$cron nice -n 20 sh $RDK_PATH/dca_utility.sh $sleep_time 1" >> $tempfile
	    fi
	    # Set new cron job from the file
	    crontab $tempfile -c $CRON_SPOOL
	    rm -rf $current_cron_file # Delete temp file
	    rm -rf $tempfile          # Delete temp file
	else
	    echo " `date` Failed to read \"schedule\" cronjob value from DCMSettings.conf." >> $DCM_LOG_FILE
	fi
    fi
done
