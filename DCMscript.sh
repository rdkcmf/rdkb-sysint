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
if [ -f /etc/telemetry2_0.properties ]; then
    . /etc/telemetry2_0.properties
fi

source /etc/log_timestamp.sh
source /lib/rdk/getpartnerid.sh
source /lib/rdk/getaccountid.sh
# Enable override only for non prod builds
if [ "$BUILD_TYPE" != "prod" ] && [ -f $PERSISTENT_PATH/dcm.properties ]; then
      . $PERSISTENT_PATH/dcm.properties
else
      . /etc/dcm.properties
fi

if [ -f /lib/rdk/utils.sh ]; then 
   . /lib/rdk/utils.sh
fi

if [ -f /etc/mount-utils/getConfigFile.sh ];then
     . /etc/mount-utils/getConfigFile.sh
fi
SIGN_FILE="/tmp/.signedRequest_$$_`date +'%s'`"
DIRECT_BLOCK_TIME=86400
DIRECT_BLOCK_FILENAME="/tmp/.lastdirectfail_dcm"

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

PEER_COMM_ID="/tmp/elxrretyt-dcm.swr"

if [ ! -f /usr/bin/GetConfigFile ];then
    echo "Error: GetConfigFile Not Found"
    exit 127
fi

IDLE_TIMEOUT=30

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

conn_str="Direct"
first_conn=useDirectRequest
sec_conn=useCodebigRequest
CodebigAvailable=0

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

IsDirectBlocked()
{
    ret=0
    if [ -f $DIRECT_BLOCK_FILENAME ]; then
        modtime=$(($(date +%s) - $(date +%s -r $DIRECT_BLOCK_FILENAME)))
        if [ "$modtime" -le "$DIRECT_BLOCK_TIME" ]; then
            echo "DCM: Last direct failed blocking is still valid, preventing direct" >>  $DCM_LOG_FILE
            ret=1
        else
            echo "DCM: Last direct failed blocking has expired, removing $DIRECT_BLOCK_FILENAME, allowing direct" >> $DCM_LOG_FILE
            rm -f $DIRECT_BLOCK_FILENAME
            ret=0
        fi
    fi
    return $ret
}

# Get the configuration of codebig settings
get_Codebigconfig()
{
   # If GetServiceUrl not available, then only direct connection available and no fallback mechanism
   if [ -f /usr/bin/GetServiceUrl ]; then
      CodebigAvailable=1
   fi

   if [ "$CodebigAvailable" -eq "1" ]; then
       CodeBigEnable=`dmcli eRT getv Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.CodeBigFirst.Enable | grep true 2>/dev/null`
   fi
   if [ "$CodebigAvailable" -eq "1" ] && [ "x$CodeBigEnable" != "x" ] ; then
      conn_str="Codebig"
      first_conn=useCodebigRequest
      sec_conn=useDirectRequest
   fi

   if [ "$CodebigAvailable" -eq 1 ]; then
      echo_t "Xconf dcm : Using $conn_str connection as the Primary" >> $DCM_LOG_FILE
   else
      echo_t "Xconf dcm : Only $conn_str connection is available" >> $DCM_LOG_FILE
   fi
}

# Direct connection Download function
useDirectRequest()
{
    # Direct connection will not be tried if .lastdirectfail exists
    IsDirectBlocked
    if [ "$?" -eq "1" ]; then
       return 1
    fi
   count=0
   while [ "$count" -lt "$RETRY_COUNT" ] ; do    
      echo_t " DCM connection type DIRECT"
      CURL_CMD="curl -w '%{http_code}\n' --tlsv1.2 --interface $EROUTER_INTERFACE $addr_type --connect-timeout $timeout -m $timeout -o  \"$FILENAME\" '$HTTPS_URL$JSONSTR'"
      echo_t "CURL_CMD: $CURL_CMD" >> $DCM_LOG_FILE
      HTTP_CODE=`result= eval $CURL_CMD`
      ret=$?

      sleep 2
      http_code=$(echo "$HTTP_CODE" | awk -F\" '{print $1}' )
      [ "x$http_code" != "x" ] || http_code=0
      echo_t "ret = $ret http_code: $http_code" >> $DCM_LOG_FILE

    # log security failure
      case $ret in
        35|51|53|54|58|59|60|64|66|77|80|82|83|90|91)
           echo_t "DCM Direct Connection Failure Attempt:$count - ret:$ret http_code:$http_code" >> $DCM_LOG_FILE
           ;;
      esac
      if [ $http_code -eq 200 ]; then
           echo_t "Direct connection success - ret:$ret http_code:$http_code" >> $DCM_LOG_FILE
           return 0
      elif [ $http_code -eq 404 ]; then 
           echo "`Timestamp` Direct connection Received HTTP $http_code Response from Xconf Server. Retry logic not needed" >> $DCM_LOG_FILE
           bypass_conn=1
           return 0  # Do not return 1, if retry for next conn type is not to be done
      else 
           if [ "$ret" -eq 0 ]; then
               echo_t "DCM Direct Connection Failure Attempt:$count - ret:$ret http_code:$http_code" >> $DCM_LOG_FILE
           fi 
           rm -rf $DCMRESPONSE
      fi
      count=$((count + 1))
      sleep $RETRY_DELAY
    done
    echo_t "DCM :Retries for Direct connection exceeded " >> $DCM_LOG_FILE
    [ "$CodebigAvailable" -ne "1" ] || [ -f $DIRECT_BLOCK_FILENAME ] || touch $DIRECT_BLOCK_FILENAME
    return 1
}

# Codebig connection Download function        
useCodebigRequest()
{
   # Do not try Codebig if CodebigAvailable != 1 (GetServiceUrl not there)
   if [ "$CodebigAvailable" -eq "0" ] ; then
       echo "DCM : Only direct connection Available" >> $DCM_LOG_FILE
       return 1
   fi
   count=0
   while [ "$count" -lt "$RETRY_COUNT" ] ; do    
      SIGN_CMD="GetServiceUrl 3 \"$JSONSTR\""
      eval $SIGN_CMD > $SIGN_FILE
      CB_SIGNED_REQUEST=`cat $SIGN_FILE`
      rm -f $SIGN_FILE
      CURL_CMD="curl -w '%{http_code}\n' --tlsv1.2 --interface $EROUTER_INTERFACE $addr_type --connect-timeout $timeout -m $timeout -o  \"$FILENAME\" \"$CB_SIGNED_REQUEST\""
      echo_t " DCM connection type CODEBIG at `echo "$CURL_CMD" | sed -ne 's#.*\(https:.*\)?.*#\1#p'`" >> $DCM_LOG_FILE
      echo_t "CURL_CMD: `echo "$CURL_CMD" | sed -ne 's#oauth_consumer_key=.*#<hidden>#p'`" >> $DCM_LOG_FILE
      HTTP_CODE=`result= eval $CURL_CMD`
      curlret=$?
      http_code=$(echo "$HTTP_CODE" | awk -F\" '{print $1}' )
      [ "x$http_code" != "x" ] || http_code=0
      echo_t "ret = $curlret http_code: $http_code" >> $DCM_LOG_FILE

      # log security failure
      case $curlret in
          35|51|53|54|58|59|60|64|66|77|80|82|83|90|91)
             echo_t "DCM Codebig Connection Failure Attempt: $count - ret:$curlret http_code:$http_code" >> $DCM_LOG_FILE
             ;;
        esac
       if [ "$http_code" -eq 200 ]; then
           echo_t "Codebig connection success - ret:$curlret http_code:$http_code" >> $DCM_LOG_FILE
           return 0
       elif [ "$http_code" -eq 404 ]; then
           echo_t "DCM Codebig connection Received HTTP $http_code Response from Xconf Server. Retry logic not needed" >> $DCM_LOG_FILE
           bypass_conn=1
           return 0  # Do not return 1, if retry for next conn type is not to be done
       else 
             if [ "$curlret" -eq 0 ]; then
                echo_t "DCM Codebig Connection Failure Attempt:$count - ret:$curlret http_code:$http_code" >> $DCM_LOG_FILE
             fi
              rm -rf $DCMRESPONSE
       fi
       count=$((count + 1))
       sleep $RETRY_DELAY
    done
    echo_t "Retries for Codebig connection exceeded " >> $DCM_LOG_FILE
    return 1
}

sendHttpRequestToServer()
{
    resp=0
    FILENAME=$1
    URL=$2

    # If interface doesnt have ipv6 address then we will force the curl to go with ipv4.
    # Otherwise we will not specify the ip address family in curl options
    addr_type=""
    [ "x`ifconfig $EROUTER_INTERFACE | grep inet6 | grep -i 'Global'`" != "x" ] || addr_type="-4"
    partnerId=$(getPartnerId)
    accountId=$(getAccountId)
    JSONSTR='estbMacAddress='$(getErouterMacAddress)'&firmwareVersion='$(getFWVersion)'&env='$(getBuildType)'&model='$(getModel)'&partnerId='${partnerId}'&accountId='${accountId}'&ecmMacAddress='$(getMacAddress)'&controllerId='$(getControllerId)'&channelMapId='$(getChannelMapId)'&vodId='$(getVODId)'&version=2'

    last_char=`echo $URL | awk '$0=$NF' FS=`
    if [ "$last_char" != "?" ]; then
        URL="$URL?"
    fi

    get_Codebigconfig
    #Retrieve protocol from current URL
    PROTO=`echo $URL | cut -d ":" -f1`
    #Replace the current protocol with https
    HTTPS_URL=`echo $URL | sed "s/$PROTO/https/g"`
    bypass_conn=0
    $first_conn || $sec_conn || { echo_t "Failed:  Unable to do Connection" >> $DCM_LOG_FILE ; return 1 ; } 
    if [ "$bypass_conn" -eq 1 ]; then
       return 1
    fi
    echo_t "HTTP request success. Processing response.." >> $DCM_LOG_FILE
    return 0
}

dropbearRecovery()
{
   dropbearPid=`ps | grep -i dropbear | grep "$ARM_INTERFACE_IP" | grep -v grep`
   if [ -z "$dropbearPid" ]; then
       echo "Dropbear instance is missing ... Recovering dropbear !!! " >> $DCM_LOG_FILE
       DROPBEAR_PARAMS_1="/tmp/.dropbear/dropcfg1$$"
       DROPBEAR_PARAMS_2="/tmp/.dropbear/dropcfg2$$"
       if [ ! -d '/tmp/.dropbear' ]; then
           echo "wan_ssh.sh: need to create dropbear dir !!! " >> $DCM_LOG_FILE
           mkdir -p /tmp/.dropbear
       fi
       echo "wan_ssh.sh: need to create dropbear files !!! " >> $DCM_LOG_FILE
       getConfigFile $DROPBEAR_PARAMS_1
       getConfigFile $DROPBEAR_PARAMS_2
       dropbear -r $DROPBEAR_PARAMS_1 -r $DROPBEAR_PARAMS_2 -E -s -p $ARM_INTERFACE_IP:22 &
       sleep 2
   fi
   rm -rf /tmp/.dropbear/*
}

# Safe wait for IP acquisition
loop=1
counter=0
while [ $loop -eq 1 ]
do
    estbIp=`getErouterIPAddress`   # This needs to be changed to wait for erouter IP address
    if [ "X$estbIp" == "X" ]; then
         echo_t "waiting for IP" >> $DCM_LOG_FILE
         sleep 2
         let counter++
    else
         loop=0
    fi
done


TELEMETRY_PATH_TEMP="$TELEMETRY_PATH/tmp"

t2Log() {
    timestamp=`date +%Y-%b-%d_%H-%M-%S`
    echo "$timestamp $*" >> $T2_0_LOGFILE
}

# Check for RFC Telemetry.Enable settings
# Internal syscfg database used by RFC parameter -  Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.Telemetry.Enable
T2_ENABLE=`syscfg get T2Enable`

t2Log "RFC value for Telemetry 2.0 Enable is $T2_ENABLE ."

if [ ! -f $T2_0_BIN ]; then
    t2Log "Unable to find $T2_0_BIN ... Switching T2 Enable to false !!!"
    T2_ENABLE="false"
fi

if [ "x$T2_ENABLE" == "xtrue" ]; then
    t2Pid=`pidof $T2_0_APP`
    if [ -z "$t2Pid" ]; then
        echo "${T2_BIN} is present, XCONF config fetch and parse will be handled by T2 implementation" >> $DCM_LOG_FILE
        t2Log "Clearing markers from $TELEMETRY_PATH"
        rm -rf $TELEMETRY_PATH
        mkdir -p $TELEMETRY_PATH
        mkdir -p $TELEMETRY_PATH_TEMP
        t2Log "Starting $T2_0_BIN daemon."
        ${T2_0_BIN}
    else
         mkdir -p $TELEMETRY_PATH_TEMP
         t2Log "telemetry daemon is already running .. Trigger from maintenance window."
         t2Log "Send signal $T2_0_APP to restart for config fetch "
         kill -9 $t2Pid
         ${T2_0_BIN}
    fi
    ## Clear any dca_utility.sh cron entries if present from T1.1 previous execution
    tempfile="/tmp/tempfile.txt"
    rm -rf $tempfile  # Delete temp file if existing
    crontab -l -c $CRON_SPOOL > $tempfile
    # Check whether any cron jobs are existing or not
    existing_cron_check=`cat $tempfile | tail -n 1`
    if [ -n "$existing_cron_check" ]; then
        rtl_cron_check=`grep -c 'dca_utility.sh' $tempfile`
        if [ $rtl_cron_check -ne 0 ]; then
            # delete entry
            sed -i '/dca_utility/d' $tempfile
            # Set new cron job from the file
            crontab $tempfile -c $CRON_SPOOL
        fi
    fi
    rm -rf $tempfile 
    exit 0
fi

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
        rm -rf $FILENAME 
        echo_t "count = $count. Sleeping $RETRY_DELAY seconds ..." >> $DCM_LOG_FILE
        exit 1
    fi

    if [ "x$DCA_MULTI_CORE_SUPPORTED" == "xyes" ]; then
            dropbearRecovery

            isPeriodicFWCheckEnabled=`syscfg get PeriodicFWCheck_Enable`
            if [ "$isPeriodicFirmwareEnabled" == "true" ]; then
               echo "XCONF SCRIPT : Calling XCONF Client firmwareSched for the updated time"
               sh /etc/firmwareSched.sh &
            fi
            
            GetConfigFile $PEER_COMM_ID
            scp -i $PEER_COMM_ID $DCMRESPONSE root@$ATOM_INTERFACE_IP:$PERSISTENT_PATH > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                scp -i $PEER_COMM_ID $DCMRESPONSE root@$ATOM_INTERFACE_IP:$PERSISTENT_PATH > /dev/null 2>&1
            fi
            echo "Signal atom to pick the XCONF config data $DCMRESPONSE and schedule telemetry !!! " >> $DCM_LOG_FILE
            ## Trigger an inotify event on ATOM 
            ssh -I $IDLE_TIMEOUT -i $PEER_COMM_ID root@$ATOM_INTERFACE_IP "/bin/echo 'xconf_update' > $TELEMETRY_INOTIFY_EVENT" > /dev/null 2>&1
            rm -f $PEER_COMM_ID
        else
            
			isPeriodicFWCheckEnabled=`syscfg get PeriodicFWCheck_Enable`
  		    if [ "$isPeriodicFirmwareEnabled" == "true" ]; then
			   echo "XCONF SCRIPT : Calling XCONF Client firmwareSched for the updated time"
			   sh /etc/firmwareSched.sh &
			fi
             
            sh /lib/rdk/dca_utility.sh 1 &
        fi
