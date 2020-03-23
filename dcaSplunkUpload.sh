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


####
## This script will be invoked upon receiving events from ATOM when processed telemetry dat is available for upload
## This cript is expected to pull the 
####

. /etc/include.properties
. /etc/device.properties

if [ -f /lib/rdk/utils.sh  ]; then
   . /lib/rdk/utils.sh
fi
source /etc/log_timestamp.sh
CODEBIG_BLOCK_TIME=1800
CODEBIG_BLOCK_FILENAME="/tmp/.lastcodebigfail_dcas"
FORCE_DIRECT_ONCE="/tmp/.forcedirectonce_dcas"
TELEMETRY_PATH="$PERSISTENT_PATH/.telemetry"
TELEMETRY_RESEND_FILE="$PERSISTENT_PATH/.resend.txt"
TELEMETRY_TEMP_RESEND_FILE="$PERSISTENT_PATH/.temp_resend.txt"

RTL_LOG_FILE="$LOG_PATH/dcmscript.log"

HTTP_FILENAME="/tmp/dca_httpret$$.txt"

DCMRESPONSE="$PERSISTENT_PATH/DCMresponse.txt"

PEER_COMM_ID="/tmp/elxrretyt-dcas.swr"

if [ ! -f /usr/bin/GetConfigFile ];then
    echo "Error: GetConfigFile Not Found"
    exit 127
fi

SIGN_FILE="/tmp/.signedRequest_$$_`date +'%s'`"

CODEBIG_MAX_ATTEMPTS=3

SLEEP_TIME_FILE="/tmp/.rtl_sleep_time.txt"
#MAX_LIMIT_RESEND=2
# Max backlog queue set to 5, after which the resend file will discard subsequent entries
MAX_CONN_QUEUE=5
DIRECT_RETRY_COUNT=2

ignoreResendList="false"

# exit if an instance is already running
if [ ! -f /tmp/.dca-splunk.upload ];then
    # store the PID
    echo $$ > /tmp/.dca-splunk.upload
else
    pid=`cat /tmp/.dca-splunk.upload`
    if [ -d /proc/$pid ];then
         echo_t "dca : previous instance of dcaSplunkUpload.sh is running."
         ignoreResendList="true"
         # Cannot exit as triggers can be from immediate log upload
    else
        rm -f /tmp/.dca-splunk.upload
        echo $$ > /tmp/.dca-splunk.upload
    fi
fi

conn_type_used=""   # Use this to check the connection success, else set to fail
conn_type="Direct" # Use this to check the connection success, else set to fail
first_conn=useDirectRequest
CodebigAvailable=0

CURL_TIMEOUT=30
TLS="--tlsv1.2" 

mkdir -p $TELEMETRY_PATH

# Processing Input Args
inputArgs=$1

#Adding support for opt override for dcm.properties file
if [ "$BUILD_TYPE" != "prod" ] && [ -f $PERSISTENT_PATH/dcm.properties ]; then
      . $PERSISTENT_PATH/dcm.properties
else
      . /etc/dcm.properties
fi
TelemetryNewEndpointAvailable=0

mTlsDCMUpload=`dmcli eRT getv Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.MTLS.mTlsDCMUpload.Enable | grep value | awk '{print $5}'`

getTelemetryEndpoint() {
    DEFAULT_DCA_UPLOAD_URL="$DCA_UPLOAD_URL"
    TelemetryEndpoint=`dmcli eRT getv Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.TelemetryEndpoint.Enable  | grep value | awk '{print $5}'`
    TelemetryEndpointURL=""
    if [ "x$TelemetryEndpoint" = "xtrue" ]; then
        TelemetryEndpointURL=`dmcli eRT getv Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.TelemetryEndpoint.URL  | grep value | awk '{print $5}'`
        if [ ! -z "$TelemetryEndpointURL" ]; then
            DCA_UPLOAD_URL="https://$TelemetryEndpointURL"
            echo_t "dca upload url from RFC is $TelemetryEndpointURL" >> $RTL_LOG_FILE
            TelemetryNewEndpointAvailable=1
        fi
    else
        if [ -f "$DCMRESPONSE" ]; then    
            TelemetryEndpointURL=`grep '"uploadRepository:URL":"' $DCMRESPONSE | awk -F 'uploadRepository:URL":' '{print $NF}' | awk -F '",' '{print $1}' | sed 's/"//g' | sed 's/}//g'`
        
            if [ ! -z "$TelemetryEndpointURL" ]; then	    
            	DCA_UPLOAD_URL="$TelemetryEndpointURL"
            	echo_t "dca upload url from dcmresponse is $TelemetryEndpointURL" >> $RTL_LOG_FILE
            fi
        fi
    fi

    if [ -z "$TelemetryEndpointURL" ]; then
        DCA_UPLOAD_URL="$DEFAULT_DCA_UPLOAD_URL"
    fi

    if [ "$mTlsDCMUpload" = "true" ]; then
       DCA_UPLOAD_URL=`echo $DCA_UPLOAD_URL | sed 's/$/\/secure/'`
       echo "MTLS Telemetry Logupload URL:$DCA_UPLOAD_URL" >> $RTL_LOG_FILE
    else
       echo "DCA Log Upload Telemetry URL:$DCA_UPLOAD_URL" >> $RTL_LOG_FILE
    fi

}

getTelemetryEndpoint

if [ -z $DCA_UPLOAD_URL ]; then
    echo_t "dca upload url read from dcm.properties is NULL"
    exit 1
fi

pidCleanup()
{
   # PID file cleanup
   if [ -f /tmp/.dca-splunk.upload ];then
        rm -rf /tmp/.dca-splunk.upload
   fi
}

IsCodebigBlocked()
{
    ret=0
    if [ -f $CODEBIG_BLOCK_FILENAME ]; then
        modtime=$(($(date +%s) - $(date +%s -r $CODEBIG_BLOCK_FILENAME)))
        if [ "$modtime" -le "$CODEBIG_BLOCK_TIME" ]; then
            echo "DCASplunk: Last Codebig failed blocking is still valid, preventing Codebig" >>  $DCM_LOG_FILE
            ret=1
        else
            echo "DCASplunk: Last Codebig failed blocking has expired, removing $CODEBIG_BLOCK_FILENAME, allowing Codebig" >> $DCM_LOG_FILE
            rm -f $CODEBIG_BLOCK_FILENAME
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
   if [ -f $FORCE_DIRECT_ONCE ]; then
      rm -f $FORCE_DIRECT_ONCE
      echo_t "dca : Last Codebig attempt failed, forcing direct once" >> $RTL_LOG_FILE
   elif [ "$CodebigAvailable" -eq "1" ] && [ "x$CodeBigEnable" != "x" ] ; then
      conn_type="Codebig"
      first_conn=useCodebigRequest
   fi

   if [ "$CodebigAvailable" -eq "1" ]; then
      echo_t "dca : Using $conn_type connection as the Primary" >> $RTL_LOG_FILE
   else
      echo_t "dca : Only $conn_type connection is available" >> $RTL_LOG_FILE
   fi
}

# Direct connection Download function
useDirectRequest()
{
    echo_t "dca$2: Using Direct commnication"
    if [ "$mTlsDCMUpload" == "true" ]; then
        echo "Log Upload requires Mutual Authentication" >> $RTL_LOG_FILE
	if [ -d /etc/ssl/certs ]; then
            if [ ! -f /usr/bin/GetConfigFile ];then
                echo "Error: GetConfigFile Not Found"
                exit 127
            fi
            ID="/tmp/geyoxnweddys"
            GetConfigFile $ID
        fi
        CURL_CMD="curl -s $TLS --key $ID --cert /etc/ssl/certs/dcm-cpe-clnt.xcal.tv.cert.pem -w '%{http_code}\n' --interface $EROUTER_INTERFACE $addr_type -H \"Accept: application/json\" -H \"Content-type: application/json\" -X POST -d '$1' -o \"$HTTP_FILENAME\" \"$DCA_UPLOAD_URL\" --connect-timeout $CURL_TIMEOUT -m $CURL_TIMEOUT"
        HTTP_CODE=`curl -s $TLS --key $ID --cert /etc/ssl/certs/dcm-cpe-clnt.xcal.tv.cert.pem -w '%{http_code}\n' --interface $EROUTER_INTERFACE $addr_type -H "Accept: application/json" -H "Content-type: application/json" -X POST -d "$1" -o "$HTTP_FILENAME" "$DCA_UPLOAD_URL" --connect-timeout $CURL_TIMEOUT -m $CURL_TIMEOUT`
        ret=$?
    else
        CURL_CMD="curl -s $TLS -w '%{http_code}\n' --interface $EROUTER_INTERFACE $addr_type -H \"Accept: application/json\" -H \"Content-type: application/json\" -X POST -d '$1' -o \"$HTTP_FILENAME\" \"$DCA_UPLOAD_URL\" --connect-timeout $CURL_TIMEOUT -m $CURL_TIMEOUT"
        HTTP_CODE=`curl -s $TLS -w '%{http_code}\n' --interface $EROUTER_INTERFACE $addr_type -H "Accept: application/json" -H "Content-type: application/json" -X POST -d "$1" -o "$HTTP_FILENAME" "$DCA_UPLOAD_URL" --connect-timeout $CURL_TIMEOUT -m $CURL_TIMEOUT`
        ret=$?
    fi
    rm -rf $ID
    echo_t "CURL_CMD: $CURL_CMD" >> $RTL_LOG_FILE
    http_code=$(echo "$HTTP_CODE" | awk -F\" '{print $1}' )
    [ "x$http_code" != "x" ] || http_code=0

    rm -f $HTTP_FILENAME

    echo_t "dca $2 : Direct Connection HTTP RESPONSE CODE : $http_code" >> $RTL_LOG_FILE
    # log security failure
    case $ret in
      35|51|53|54|58|59|60|64|66|77|80|82|83|90|91)
         echo_t "dca$2: Direct Connection Failure - ret:$ret http_code:$http_code" >> $RTL_LOG_FILE
         ;;
    esac
    if [ $http_code -eq 200 ]; then
        echo_t "dca$2: Direct connection success - ret:$ret http_code:$http_code" >> $RTL_LOG_FILE
        # Use direct connection for rest of the connections
        conn_type_used="Direct"
        return 0
    fi
    if [ "$ret" -eq 0 ]; then
        echo_t "dca$2: Direct Connection Failure - ret:$ret http_code:$http_code" >> $RTL_LOG_FILE
    else
        echo_t "dca$2: Splunk Direct Connection curl error - ret:$ret http_code:$http_code" >> $RTL_LOG_FILE
    fi
    echo "dcaSplunkUpload: Retries for direct connection exceeded "
    sleep 10
    return 1
}

# Codebig connection Download function
useCodebigRequest()
{
    # Do not try Codebig if CodebigAvailable != 1 (GetServiceUrl not there)
    if [ "$CodebigAvailable" -eq "0" ] ; then
       echo "dca$2 : Only direct connection Available"
       return 1
    fi

    if [ "x$CodeBigEnable" = "x" ] ; then
       echo_t "dca$2 : Codebig connection attempts are disabled through RFC. Exiting !!!" >> $RTL_LOG_FILE
       return 1
    fi

    IsCodebigBlocked
    if [ "$?" -eq "1" ] ; then
        return 1
    fi

    retries=0
    while [ "$retries" -lt "$CODEBIG_MAX_ATTEMPTS" ]
    do
        if [ "$TelemetryNewEndpointAvailable" -eq "1" ]; then
            SIGN_CMD="GetServiceUrl 10 "
        else
            SIGN_CMD="GetServiceUrl 9 "
        fi
        eval $SIGN_CMD > $SIGN_FILE
        CB_SIGNED_REQUEST=`cat $SIGN_FILE`
        rm -f $SIGN_FILE
        CURL_CMD="curl $TLS -w '%{http_code}\n' --interface $EROUTER_INTERFACE $addr_type -H \"Accept: application/json\" -H \"Content-type: application/json\" -X POST -d '$1' -o \"$HTTP_FILENAME\" \"$CB_SIGNED_REQUEST\" --connect-timeout $CURL_TIMEOUT -m $CURL_TIMEOUT"
        echo_t "dca$2: Using Codebig connection at `echo "$CURL_CMD" | sed -ne 's#.*\(https:.*\)?.*#\1#p'`" >> $RTL_LOG_FILE
        echo_t "CURL_CMD: `echo "$CURL_CMD" | sed -ne 's#oauth_consumer_key=.*oauth_signature=.* --#<hidden> --#p'`" >> $RTL_LOG_FILE
        HTTP_CODE=`curl $TLS -w '%{http_code}\n' --interface $EROUTER_INTERFACE $addr_type -H "Accept: application/json" -H "Content-type: application/json" -X POST -d "$1" -o "$HTTP_FILENAME" "$CB_SIGNED_REQUEST" --connect-timeout $CURL_TIMEOUT -m $CURL_TIMEOUT`
        curlret=$?
        http_code=$(echo "$HTTP_CODE" | awk -F\" '{print $1}' )
        [ "x$http_code" != "x" ] || http_code=0
    
        rm -f $HTTP_FILENAME
        # log security failure
        echo_t "dca $2 : Codebig Connection HTTP RESPONSE CODE : $http_code" >> $RTL_LOG_FILE
        case $curlret in
            35|51|53|54|58|59|60|64|66|77|80|82|83|90|91)
               echo_t "dca$2: Codebig Connection Failure - ret:$curlret http_code:$http_code" >> $RTL_LOG_FILE
               ;;
        esac
        if [ "$http_code" -eq 200 ]; then
             echo_t "dca$2: Codebig connection success - ret:$curlret http_code:$http_code" >> $RTL_LOG_FILE
             conn_type_used="Codebig"
             return 0
        fi
        if [ "$curlret" -eq 0 ]; then
            echo_t "dca$2: Codebig Connection Failure - ret:$curlret http_code:$http_code" >> $RTL_LOG_FILE
        else
            echo_t "dca$2: Splunk Codebig Connection curl error - ret:$curlret http_code:$http_code" >> $RTL_LOG_FILE
        fi
        if [ "$retries" -lt "$CODEBIG_MAX_ATTEMPTS" ]; then
            if [ "$retries" -eq "0" ]; then
                sleep 10
            else
                sleep 30
            fi
        fi
        retries=`expr $retries + 1`
    done
    echo "dcaSplunkUpload: Retries for Codebig connection exceeded "
    [ -f $CODEBIG_BLOCK_FILENAME ] || touch $CODEBIG_BLOCK_FILENAME
    touch $FORCE_DIRECT_ONCE
    return 1
}

timestamp=`date +%Y-%b-%d_%H-%M-%S`
#main app
estbMac=`getErouterMacAddress`
cur_time=`date "+%Y-%m-%d %H:%M:%S"`

# If interface doesnt have ipv6 address then we will force the curl to go with ipv4.
# Otherwise we will not specify the ip address family in curl options
addr_type=""
[ "x`ifconfig $EROUTER_INTERFACE | grep inet6 | grep -i 'Global'`" != "x" ] || addr_type="-4"

if [ "x$DCA_MULTI_CORE_SUPPORTED" = "xyes" ]; then
   ##  1]  Pull processed data from ATOM 
   rm -f $TELEMETRY_JSON_RESPONSE

   
   GetConfigFile $PEER_COMM_ID
   scp -i $PEER_COMM_ID root@$ATOM_INTERFACE_IP:$TELEMETRY_JSON_RESPONSE $TELEMETRY_JSON_RESPONSE > /dev/null 2>&1
   if [ $? -ne 0 ]; then
       scp -i $PEER_COMM_ID root@$ATOM_INTERFACE_IP:$TELEMETRY_JSON_RESPONSE $TELEMETRY_JSON_RESPONSE > /dev/null 2>&1
   fi
   echo_t "Copied $TELEMETRY_JSON_RESPONSE " >> $RTL_LOG_FILE 
   rm -f $PEER_COMM_ID
   sleep 2
fi

# Add the erouter MAC address from ARM as this is not available in ATOM
sed -i -e "s/ErouterMacAddress/$estbMac/g" $TELEMETRY_JSON_RESPONSE


if [ ! -f $SLEEP_TIME_FILE ]; then
    if [ -f $DCMRESPONSE ]; then
        cron=`grep -i TelemetryProfile $DCMRESPONSE | awk -F '"schedule":' '{print $NF}' | awk -F "," '{print $1}' | sed 's/://g' | sed 's/"//g' | sed -e 's/^[ ]//' | sed -e 's/^[ ]//'`
    fi

    if [ -n "$cron" ]; then
        sleep_time=`echo "$cron" | awk -F '/' '{print $2}' | cut -d ' ' -f1`
    fi 

    if [ -n "$sleep_time" ];then
        sleep_time=`expr $sleep_time - 1` #Subtract 1 miute from it
        sleep_time=`expr $sleep_time \* 60` #Make it to seconds
        # Adding generic RANDOM number implementation as sh in RDK_B doesn't support RANDOM
        RANDOM=`awk -v min=5 -v max=10 'BEGIN{srand(); print int(min+rand()*(max-min+1)*(max-min+1)*1000)}'`
        sleep_time=$(($RANDOM%$sleep_time)) #Generate a random value out of it
        echo "$sleep_time" > $SLEEP_TIME_FILE
    else
        sleep_time=10
    fi
else 
    sleep_time=`cat $SLEEP_TIME_FILE`
fi

if [ -z "$sleep_time" ];then
    sleep_time=10
fi

if [ "$inputArgs" = "logbackup_without_upload" ];then
      echo_t "log backup during bootup, Will upload on later call..!"
      if [ -f $TELEMETRY_JSON_RESPONSE ]; then
           outputJson=`cat $TELEMETRY_JSON_RESPONSE`
      fi
      if [ ! -f $TELEMETRY_JSON_RESPONSE ] || [ "x$outputJson" = "x" ] ; then
               echo_t "dca: Unable to find Json message or Json is empty." >> $RTL_LOG_FILE
         if [ ! -f /etc/os-release ];then pidCleanup; fi
         exit 0
      fi
      if [ -f $TELEMETRY_RESEND_FILE ]; then
            #If resend queue has already reached MAX_CONN_QUEUE entries then remove recent two
            if [ "`cat $TELEMETRY_RESEND_FILE | wc -l`" -ge "$MAX_CONN_QUEUE" ]; then
                echo_t "resend queue size at its max. removing recent two entries" >> $RTL_LOG_FILE
                sed -i '1,2d' $TELEMETRY_RESEND_FILE
            fi
            mv $TELEMETRY_RESEND_FILE $TELEMETRY_TEMP_RESEND_FILE
      fi
      # ensure that Json is put at the top of the queue
      echo "$outputJson" > $TELEMETRY_RESEND_FILE
      if [ -f $TELEMETRY_TEMP_RESEND_FILE ] ; then
         cat $TELEMETRY_TEMP_RESEND_FILE >> $TELEMETRY_RESEND_FILE
         rm -f $TELEMETRY_TEMP_RESEND_FILE
      fi
      if [ ! -f /etc/os-release ];then pidCleanup; fi
      exit 0
fi
get_Codebigconfig
##  2] Check for unsuccessful posts from previous execution in resend que.
##  If present repost either with appending to existing or as independent post
if [ -f $TELEMETRY_RESEND_FILE ] && [ "x$ignoreResendList" != "xtrue" ]; then
    rm -f $TELEMETRY_TEMP_RESEND_FILE
    while read resend
    do
        echo_t "dca resend : $resend" >> $RTL_LOG_FILE 
        $first_conn "$resend" "resend" || conn_type_used="Fail" 

        if [ "x$conn_type_used" = "xFail" ] ; then 
           echo "$resend" >> $TELEMETRY_TEMP_RESEND_FILE
           echo_t "dca Connecion failed for this Json : requeuing back"  >> $RTL_LOG_FILE 
        fi 
        echo_t "dca Attempting next Json in the queue "  >> $RTL_LOG_FILE 
        sleep 10 
   done < $TELEMETRY_RESEND_FILE
   sleep 2
   rm -f $TELEMETRY_RESEND_FILE
fi

##  3] Attempt to post current message. Check for status if failed add it to resend queue
if [ -f $TELEMETRY_JSON_RESPONSE ]; then
   outputJson=`cat $TELEMETRY_JSON_RESPONSE`
fi
if [ ! -f $TELEMETRY_JSON_RESPONSE ] || [ "x$outputJson" = "x" ] ; then
    echo_t "dca: Unable to find Json message or Json is empty." >> $RTL_LOG_FILE
    [ ! -f $TELEMETRY_TEMP_RESEND_FILE ] ||  mv $TELEMETRY_TEMP_RESEND_FILE $TELEMETRY_RESEND_FILE
    if [ ! -f /etc/os-release ];then pidCleanup; fi
    exit 0
fi

echo "$outputJson" > $TELEMETRY_RESEND_FILE
# sleep for random time before upload to avoid bulk requests on splunk server
echo_t "dca: Sleeping for $sleep_time before upload." >> $RTL_LOG_FILE
sleep $sleep_time
timestamp=`date +%Y-%b-%d_%H-%M-%S`
$first_conn "$outputJson"  ||  conn_type_used="Fail" 
if [ "x$conn_type_used" != "xFail" ]; then
    echo_t "dca: Json message successfully submitted." >> $RTL_LOG_FILE
    rm -f $TELEMETRY_RESEND_FILE
    [ ! -f $TELEMETRY_TEMP_RESEND_FILE ] ||  mv $TELEMETRY_TEMP_RESEND_FILE $TELEMETRY_RESEND_FILE
else
   if [ -f $TELEMETRY_TEMP_RESEND_FILE ] ; then
       if [ "`cat $TELEMETRY_TEMP_RESEND_FILE | wc -l `" -ge "$MAX_CONN_QUEUE" ]; then
            echo_t "dca: resend queue size has already reached MAX_CONN_QUEUE. Not adding anymore entries" >> $RTL_LOG_FILE
            mv $TELEMETRY_TEMP_RESEND_FILE $TELEMETRY_RESEND_FILE
       else
            cat $TELEMETRY_TEMP_RESEND_FILE >> $TELEMETRY_RESEND_FILE
            echo_t "dca: Json message submit failed. Adding message to resend queue" >> $RTL_LOG_FILE
       fi
       rm -f $TELEMETRY_TEMP_RESEND_FILE
    fi
fi
rm -f $TELEMETRY_JSON_RESPONSE
# PID file cleanup
if [ ! -f /etc/os-release ];then pidCleanup; fi
