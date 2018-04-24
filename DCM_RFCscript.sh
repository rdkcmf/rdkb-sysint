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
source /lib/rdk/getpartnerid.sh
DCM_RFC_LOG_FILE="$LOG_PATH/dcmrfc.log"
DCMRFCRESPONSE="/tmp/rfcresponse.json"
DCM_PARSER_RESPONSE="/tmp/rfc_configdata.txt"

# Enable override only for non prod builds
if [ "$BUILD_TYPE" != "prod" ] && [ -f $PERSISTENT_PATH/dcm.properties ]; then
      echo_t "Reading from /nvram/dcm.properties file" >> $DCM_RFC_LOG_FILE
      . $PERSISTENT_PATH/dcm.properties
else
      echo_t "Reading from /etc/dcm.properties file" >> $DCM_RFC_LOG_FILE
      . /etc/dcm.properties
fi

# creeate RAM based folder

if [ -z $RFC_RAM_PATH ]; then
    RFC_RAM_PATH="/tmp/RFC"
fi

if [ ! -d $RFC_RAM_PATH ]; then
    mkdir -p $RFC_RAM_PATH
    echo "RFC: creating $RFC_RAM_PATH" >> $DCM_RFC_LOG_FILE
fi

if [ -f /lib/rdk/utils.sh ]; then 
   . /lib/rdk/utils.sh
fi

SIGN_FILE="/tmp/.signedRequest_$$_`date +'%s'`"
DIRECT_BLOCK_TIME=86400
DIRECT_BLOCK_FILENAME="/tmp/.lastdirectfail_rfc"
GET="dmcli eRT getv"
SET="dmcli eRT setv"

conn_str="Direct"
first_conn=useDirectRequest
sec_conn=useCodebigRequest
CodebigAvailable=0

timeout=30
RETRY_COUNT=3

IsDirectBlocked()
{
    ret=0
    if [ -f $DIRECT_BLOCK_FILENAME ]; then
        modtime=$(($(date +%s) - $(date +%s -r $DIRECT_BLOCK_FILENAME)))
        if [ "$modtime" -le "$DIRECT_BLOCK_TIME" ]; then
            echo "Xconf dcm rfc: Last direct failed blocking is still valid, preventing direct" >> $DCM_RFC_LOG_FILE
            ret=1
        else
            echo "Xconf dcm rfc: Last direct failed blocking has expired, removing $DIRECT_BLOCK_FILENAME, allowing direct" >> $DCM_RFC_LOG_FILE
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
      echo_t "Xconf dcm rfc : Using $conn_str connection as the Primary" >> $DCM_RFC_LOG_FILE
   else
      echo_t "Xconf dcm rfc : Only $conn_str connection is available" >> $DCM_RFC_LOG_FILE
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
    retries=0
    while [ "$retries" -lt $RETRY_COUNT ]
    do
        echo_t "Connect to Xconf dcm rfc end point using DIRECT " >> $DCM_RFC_LOG_FILE
        CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' --interface $EROUTER_INTERFACE $addr_type --connect-timeout $timeout -m $timeout -o  \"$DCMRFCRESPONSE\" '$DCM_RFC_SERVER_URL$JSONSTR'"
        echo_t "CURL_CMD: $CURL_CMD" >> $DCM_RFC_LOG_FILE
        HTTP_CODE=`result= eval $CURL_CMD`
        ret=$?
        sleep 2
        http_code=$(echo "$HTTP_CODE" | awk -F\" '{print $1}' )
        [ "x$http_code" != "x" ] || http_code=0

        if [ $http_code -eq 200 ]; then
           echo_t "Direct connection success ($http_code) " >> $DCM_RFC_LOG_FILE
           return 0
        elif [ $http_code -eq 404 ]; then
            echo_t "Direct connection Received HTTP $http_code Response from Xconf Server. Retry logic not needed" >> $DCM_RFC_LOG_FILE
            bypass_conn=1
            return 0  # Do not return 1, if retry for next conn type is not to be done
        else
           echo_t "Xconf dcm rfc Direct Connection Failure : Attempt:$retries - ret:$ret http_code:$http_code" >> $DCM_RFC_LOG_FILE
        fi
   retries=`expr $retries + 1`
   sleep 10
   done
   echo_t "Retries for Direct connection exceeded " >> $DCM_RFC_LOG_FILE
   [ "$CodebigAvailable" -ne "1" ] || [ -f $DIRECT_BLOCK_FILENAME ] || touch $DIRECT_BLOCK_FILENAME
   return 1
}
        
# Codebig connection Download function        
useCodebigRequest() 
{
   # Do not try Codebig if CodebigAvailable != 1 (GetServiceUrl not there)
   if [ "$CodebigAvailable" -eq "0" ] ; then
       echo "DCM RFC : Only direct connection Available" >> $DCM_RFC_LOG_FILE
       return 1
   fi
    retries=0
    while [ "$retries" -lt $RETRY_COUNT ]
    do
        SIGN_CMD="GetServiceUrl 8 \"$JSONSTR\""
        eval $SIGN_CMD > $SIGN_FILE
        CB_SIGNED_REQUEST=`cat $SIGN_FILE`
        rm -f $SIGN_FILE
        SIGN_CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' --interface $EROUTER_INTERFACE $addr_type --connect-timeout $timeout -m $timeout -o  \"$DCMRFCRESPONSE\" \"$CB_SIGNED_REQUEST\""
        echo_t "Connect to Xconf dcm rfc end point using CODEBIG at `echo "$SIGN_CURL_CMD" | sed -ne 's#.*\(https:.*\)?.*#\1#p'`" >> $DCM_RFC_LOG_FILE
        echo_t "CURL_CMD: `echo "$SIGN_CURL_CMD" | sed -ne 's#oauth_consumer_key=.*#<hidden>#p'`" >> $DCM_RFC_LOG_FILE
        HTTP_CODE=`result= eval $SIGN_CURL_CMD`
        ret=$?
        http_code=$(echo "$HTTP_CODE" | awk -F\" '{print $1}' )
        [ "x$http_code" != "x" ] || http_code=0

        if [ $http_code -eq 200 ]; then
             echo_t "Codebig connection success ($http_code)" >> $DCM_RFC_LOG_FILE
             return 0;
        elif [ $http_code -eq 404 ]; then
            echo_t "Codebig connection Received HTTP $http_code Response from Xconf Server. Retry logic not needed" >> $DCM_RFC_LOG_FILE
            bypass_conn=1
            return 0  # Do not return 1, if retry for next conn type is not to be done
        else
           echo_t "Xconf dcm rfc Codebig Connection Failure Attempt:$retries - ret:$ret http_code:$http_code" >> $DCM_RFC_LOG_FILE
        fi
        retries=`expr $retries + 1`
        sleep 10
    done
    echo_t "Retries for Codebig connection exceeded " >> $DCM_RFC_LOG_FILE
    return 1
}
getQueryDcm()
{
    echo_t "server url is  $DCM_RFC_SERVER_URL" >> $DCM_RFC_LOG_FILE

    # If interface doesnt have ipv6 address then we will force the curl to go with ipv4.
    # Otherwise we will not specify the ip address family in curl options
    addr_type=""
    [ "x`ifconfig $EROUTER_INTERFACE | grep inet6 | grep -i 'Global'`" != "x" ] || addr_type="-4"

      partnerId=$(getPartnerId)
      JSONSTR='estbMacAddress='$(getErouterMacAddress)'&firmwareVersion='$(getFWVersion)'&env='$(getBuildType)'&model='$(getModel)'&partnerId='${partnerId}'&ecmMacAddress='$(getMacAddress)'&controllerId='$(getControllerId)'&channelMapId='$(getChannelMapId)'&vodId='$(getVODId)'&version=2'

    last_char=`echo $DCM_RFC_SERVER_URL | awk '$0=$NF' FS=`
    if [ "$last_char" != "?" ]; then
        DCM_RFC_SERVER_URL="$DCM_RFC_SERVER_URL?"
    fi
    bypass_conn=0
    get_Codebigconfig
    # return success - 0 for now, if failure. 
    $first_conn || $sec_conn || { echo_t "Failed : Unable to do Connection" >> $DCM_RFC_LOG_FILE; return 1; }
    if [ "$bypass_conn" -eq 1 ]; then
       return 1
    fi
    echo_t "Curl success" >> $DCM_RFC_LOG_FILE
    if [ -e /usr/bin/dcmjsonparser ]; then
       echo_t "dcmjsonparser binary present" >> $DCM_RFC_LOG_FILE
       /usr/bin/dcmjsonparser $DCMRFCRESPONSE  >> $DCM_RFC_LOG_FILE

       if [ -f $DCM_PARSER_RESPONSE ] && [ "x`cat $DCM_PARSER_RESPONSE`" != "x" ]; then 
          echo_t "$DCM_PARSER_RESPONSE file is present" >> $DCM_RFC_LOG_FILE
          file=$DCM_PARSER_RESPONSE
          $SET Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.CodebigSupport bool false
          $SET Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.Container bool false
          while read line; do
              key=`echo $line|cut -d ":" -f1`
              value=`echo $line|cut -d ":" -f2`
              echo_t "key=$key value=$value" >> $DCM_RFC_LOG_FILE
              parseConfigValue $key $value     
          done < $file
       else
          echo_t "$DCM_PARSER_RESPONSE is not present" >> $DCM_RFC_LOG_FILE  
       fi

       if [ -f "$RFC_POSTPROCESS" ]
       then
          echo_t "Calling RFCpostprocessing" >> $DCM_RFC_LOG_FILE
          $RFC_POSTPROCESS &
       else
          echo_t "ERROR: No $RFC_POSTPROCESS script" >> $DCM_RFC_LOG_FILE
       fi

    else
       echo_t "binary dcmjsonparse is not present" >> $DCM_RFC_LOG_FILE
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

##GET parameter datatype using dmcli and do SET
parseConfigValue()
{
    configKey=$1
    configValue=$2
    #Remove tr181
    paramName=`echo $configKey | grep tr181 | tr -s ' ' | cut -d "." -f2- `
    
    #Do dmcli for paramName preceded with tr181 
    if [ -n "$paramName" ]; then
        echo_t "Parameter name $paramName" >> $DCM_RFC_LOG_FILE 
        echo_t "Parameter value  $configValue" >> $DCM_RFC_LOG_FILE
        #dmcli GET 
        paramType=`$GET $paramName | grep type| tr -s ' ' |cut -f3 -d" " | tr , " "`
        if [ -n "$paramType" ]; then
            echo_t "paramType is $paramType" >> $DCM_RFC_LOG_FILE
            #dmcli get value 
            paramValue=`$GET $paramName | grep value: | cut -d':' -f3 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'`
			echo_t "old parameter value $paramValue " >> $DCM_RFC_LOG_FILE
            if [ "$paramValue" != "$configValue" ]; then
		        #dmcli SET
		        paramSet=`$SET $paramName $paramType $configValue | grep succeed| tr -s ' ' `
		        if [ -n "$paramSet" ]; then
		            echo_t "dmcli SET success for $paramName with value $configValue" >> $DCM_RFC_LOG_FILE
		        else
		            echo_t "dmcli SET failed for $paramName with value $configValue" >> $DCM_RFC_LOG_FILE
		        fi
		    else
		    	echo_t "For param $paramName new and old values are same" >> $DCM_RFC_LOG_FILE
		    fi
        else
            echo_t "dmcli GET failed for $paramName " >> $DCM_RFC_LOG_FILE
        fi
    fi

}


if [ -f $DCM_PARSER_RESPONSE ]; then
    rm -rf $DCM_PARSER_RESPONSE
fi
#Call getQueryDcm to GET dcm response
getQueryDcm

