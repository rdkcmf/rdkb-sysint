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

if [ -f /lib/rdk/utils.sh  ]; then 
   . /lib/rdk/utils.sh
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
TELEMETRY_INOTIFY_FOLDER=/telemetry
TELEMETRY_INOTIFY_EVENT="$TELEMETRY_INOTIFY_FOLDER/eventType.cmd"

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

# File to save curl response 
#FILENAME="$PERSISTENT_PATH/DCMresponse.txt"
DCMRESPONSE="$PERSISTENT_PATH/DCMresponse.txt"
# File to save http code
HTTP_CODE="$PERSISTENT_PATH/http_code"
rm -rf $HTTP_CODE
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
    sleep 2
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
    fi
    echo "`date` resp = $resp" >> $DCM_LOG_FILE
    return $resp
}


# Safe wait for IP acquisition
loop=1
counter=0
while [ $loop -eq 1 ]
do
    estbIp=`getCMIPAddress`   # This needs to be changed to wait for erouter IP address
    if [ "X$estbIp" == "X" ]; then
         echo "`date` waiting for IP" >> $DCM_LOG_FILE
         sleep 2
         let counter++
    else
         loop=0
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

    sleep 5

    if [ $ret -ne 0 ]; then
        echo "`date` Processing response failed." >> $DCM_LOG_FILE
        rm -rf $FILENAME $HTTP_CODE
        count=$((count + 1))
        if [ $count -ge $RETRY_COUNT ]; then
            echo " `date` $RETRY_COUNT tries failed. Giving up..." >> $DCM_LOG_FILE
            echo 0 > $DCMFLAG
            exit 1
        fi
        echo "`date` count = $count. Sleeping $RETRY_DELAY seconds ..." >> $DCM_LOG_FILE
        sleep $RETRY_DELAY
    else
        loop=0

        if [ "x$DCA_MULTI_CORE_SUPPORTED" == "xyes" ]; then
            scp $DCMRESPONSE root@$ATOM_INTERFACE_IP:$PERSISTENT_PATH
            if [ $? -ne 0 ]; then
                scp $DCMRESPONSE root@$ATOM_INTERFACE_IP:$PERSISTENT_PATH
            fi
            echo "Signal atom to pick the XCONF config data $DCMRESPONSE and schedule telemetry !!! " >> $DCM_LOG_FILE
            ## Trigger an inotify event on ATOM 
            ssh root@$ATOM_INTERFACE_IP "/bin/echo 'xconf_update' > $TELEMETRY_INOTIFY_EVENT"
        else
            sh /lib/rdk/dca_utility.sh 1 &
        fi
    fi
done
