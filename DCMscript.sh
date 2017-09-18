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
#

. /etc/include.properties
. /etc/device.properties

source /etc/log_timestamp.sh
# Enable override only for non prod builds
if [ "$BUILD_TYPE" != "prod" ] && [ -f $PERSISTENT_PATH/dcm.properties ]; then
      . $PERSISTENT_PATH/dcm.properties
else
      . /etc/dcm.properties
fi

if [ -f /lib/rdk/utils.sh ]; then 
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
TELEMETRY_INOTIFY_FOLDER="/telemetry"
TELEMETRY_INOTIFY_EVENT="$TELEMETRY_INOTIFY_FOLDER/eventType.cmd"
DCMRESPONSE="$PERSISTENT_PATH/DCMresponse.txt"
TELEMETRY_TEMP_RESEND_FILE="$PERSISTENT_PATH/.temp_resend.txt"

PEER_COMM_DAT="/etc/dropbear/elxrretyt.swr"
PEER_COMM_ID="/tmp/elxrretyt-$$.swr"
CONFIGPARAMGEN="/usr/bin/configparamgen"

# http header
HTTP_HEADERS='Content-Type: application/json'
## RETRY DELAY in secs
RETRY_DELAY=60
## RETRY COUNT
RETRY_COUNT=3

echo_t "Starting execution of DCMscript.sh" >> $DCM_LOG_FILE

if [ $# -ne 5 ]; then
    echo_t "Argument does not match" >> $DCM_LOG_FILE
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

echo_t "URL: $URL" >> $DCM_LOG_FILE
echo_t "DCM_TFTP_SERVER: $tftp_server" >> $DCM_LOG_FILE
echo_t "BOOT_FLAG: $reboot_flag" >> $DCM_LOG_FILE
echo_t "CHECK_ON_REBOOT: $checkon_reboot" >> $DCM_LOG_FILE

rm -f $TELEMETRY_TEMP_RESEND_FILE

# This override doesn't happen during device bootup
if [ -f $DCMRESPONSE ]; then
    Check_URL=`grep 'urn:settings:ConfigurationServiceURL' $DCMRESPONSE | cut -d '=' -f2 | head -n 1`
    if [ -n "$Check_URL" ]; then
        URL=`grep 'urn:settings:ConfigurationServiceURL' $DCMRESPONSE | cut -d '=' -f2 | sed 's/^"//' | sed 's/"$//' | head -n 1`
        #last_char=`echo $URL | sed -e 's/\(^.*\)\(.$\)/\2/'`
        last_char=`echo $URL | awk '$0=$NF' FS=`
        if [ "$last_char" != "?" ]; then
            URL="$URL?"
        fi
    fi
fi

# File to save curl response 
#FILENAME="$PERSISTENT_PATH/DCMresponse.txt"
# File to save http code
HTTP_CODE="$PERSISTENT_PATH/http_code"
rm -rf $HTTP_CODE
# Timeout value
timeout=30
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

    #Retrieve protocol from current URL
    PROTO=`echo $URL | cut -d ":" -f1`
    #Replace the current protocol with https
    HTTPS_URL=`echo $URL | sed "s/$PROTO/https/g"`

    CURL_CMD="curl -w '%{http_code}\n' --tlsv1.2 --interface $EROUTER_INTERFACE --connect-timeout $timeout -m $timeout -o  \"$FILENAME\" '$HTTPS_URL$JSONSTR'"
    echo_t "CURL_CMD: $CURL_CMD" >> $DCM_LOG_FILE
    result= eval $CURL_CMD > $HTTP_CODE
    ret=$?

    sleep 2
    http_code=$(awk -F\" '{print $1}' $HTTP_CODE)
    echo_t "ret = $ret http_code: $http_code" >> $DCM_LOG_FILE
	
    # Retry for STBs hosted in open internet
    if [ ! -z "$CODEBIG_ENABLED" -a "$CODEBIG_ENABLED"!=" " -a $http_code -eq 000 ] && [ -f /usr/bin/configparamgen ]; then
        echo_t "Retry attempt to get logupload setting for STB in wild " >> $DCM_LOG_FILE

        SIGN_CMD="configparamgen 3 \"$JSONSTR\""
        eval $SIGN_CMD > /tmp/.signedRequest
        CB_SIGNED_REQUEST=`cat /tmp/.signedRequest`
        rm -f /tmp/.signedRequest
        CURL_CMD="curl -w '%{http_code}\n' --tlsv1.2 --interface $EROUTER_INTERFACE --connect-timeout $timeout -m $timeout -o  \"$FILENAME\" \"$CB_SIGNED_REQUEST\""
        result= eval $CURL_CMD > $HTTP_CODE
        http_code=$(awk -F\" '{print $1}' $HTTP_CODE)
        ret=$?
    fi

    if [ $ret = 0 ] && [ "$http_code" = "404" ] ; then
         echo "`Timestamp` Received HTTP 404 Response from Xconf Server. Retry logic not needed" >> $DCM_LOG_FILE
	 resp=1
    elif [ $ret -ne 0 -o $http_code -ne 200 ] ; then
        echo_t "HTTP request failed" >> $DCM_LOG_FILE
        rm -rf $DCMRESPONSE
        resp=1
    else
        echo_t "HTTP request success. Processing response.." >> $DCM_LOG_FILE
    fi
    echo_t "resp = $resp" >> $DCM_LOG_FILE
    return $resp
}

dropbearRecovery()
{
   dropbearPid=`ps | grep -i dropbear | grep "$ARM_INTERFACE_IP" | grep -v grep`
   if [ -z "$dropbearPid" ]; then
       echo "Dropbear instance is missing ... Recovering dropbear !!! " >> $DCM_LOG_FILE
       dropbear -E -s -p $ARM_INTERFACE_IP:22 &
       sleep 2
   fi
}

# Safe wait for IP acquisition
loop=1
counter=0
while [ $loop -eq 1 ]
do

    estbIp=`getErouterIPAddress`
    if [ "X$estbIp" == "X" ] || [ $estbIp == "0.0.0.0" ]; then
         echo_t "waiting for IP" >> $DCM_LOG_FILE
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
	echo_t "sendHttpRequestToServer returned $ret" >> $DCM_LOG_FILE
    else
	ret=0
	echo_t "sendHttpRequestToServer has not executed since the value of 'checkon_reboot' is $checkon_reboot" >> $DCM_LOG_FILE
    fi                

    sleep 5

    if [ $ret -ne 0 ]; then
        echo_t "Processing response failed." >> $DCM_LOG_FILE
        rm -rf $FILENAME $HTTP_CODE
        count=$((count + 1))
        if [ $count -ge $RETRY_COUNT ]; then
            echo_t " $RETRY_COUNT tries failed. Giving up..." >> $DCM_LOG_FILE
            echo 0 > $DCMFLAG
            exit 1
        fi
        echo_t "count = $count. Sleeping $RETRY_DELAY seconds ..." >> $DCM_LOG_FILE
        sleep $RETRY_DELAY
    else
        loop=0

        if [ "x$DCA_MULTI_CORE_SUPPORTED" == "xyes" ]; then
            dropbearRecovery

            isPeriodicFWCheckEnabled=`syscfg get PeriodicFWCheck_Enable`
            if [ "$isPeriodicFirmwareEnabled" == "true" ]; then
               echo "XCONF SCRIPT : Calling XCONF Client firmwareSched for the updated time"
               sh /etc/firmwareSched.sh &
            fi
            
            $CONFIGPARAMGEN jx $PEER_COMM_DAT $PEER_COMM_ID
            scp -i $PEER_COMM_ID $DCMRESPONSE root@$ATOM_INTERFACE_IP:$PERSISTENT_PATH > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                scp -i $PEER_COMM_ID $DCMRESPONSE root@$ATOM_INTERFACE_IP:$PERSISTENT_PATH > /dev/null 2>&1
            fi
            echo "Signal atom to pick the XCONF config data $DCMRESPONSE and schedule telemetry !!! " >> $DCM_LOG_FILE
            ## Trigger an inotify event on ATOM 
            ssh -i $PEER_COMM_ID root@$ATOM_INTERFACE_IP "/bin/echo 'xconf_update' > $TELEMETRY_INOTIFY_EVENT" > /dev/null 2>&1
            rm -f $PEER_COMM_ID
        else
            
			isPeriodicFWCheckEnabled=`syscfg get PeriodicFWCheck_Enable`
  		    if [ "$isPeriodicFirmwareEnabled" == "true" ]; then
			   echo "XCONF SCRIPT : Calling XCONF Client firmwareSched for the updated time"
			   sh /etc/firmwareSched.sh &
			fi
             
            sh /lib/rdk/dca_utility.sh 1 &
        fi
    fi
done

