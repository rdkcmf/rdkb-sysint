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

if [ -f /lib/rdk/utils.sh ]; then 
   . /lib/rdk/utils.sh
fi

GET="dmcli eRT getv"
SET="dmcli eRT setv"
timeout=30
RETRY_COUNT=3

getQueryDcm()
{
    echo_t "server url is  $DCM_RFC_SERVER_URL" >> $DCM_RFC_LOG_FILE
      JSONSTR='estbMacAddress='$(getErouterMacAddress)'&firmwareVersion='$(getFWVersion)'&env='$(getBuildType)'&model='$(getModel)'&ecmMacAddress='$(getMacAddress)'&controllerId='$(getControllerId)'&channelMapId='$(getChannelMapId)'&vodId='$(getVODId)'&version=2'

    last_char=`echo $DCM_RFC_SERVER_URL | awk '$0=$NF' FS=`
    if [ "$last_char" != "?" ]; then
        DCM_RFC_SERVER_URL="$DCM_RFC_SERVER_URL?"
    fi
    
    retries=0
    while [ "$retries" -lt $RETRY_COUNT ]
    do
        CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' --interface $EROUTER_INTERFACE --connect-timeout $timeout -m $timeout -o  \"$DCMRFCRESPONSE\" '$DCM_RFC_SERVER_URL$JSONSTR'"
        echo_t "CURL_CMD: $CURL_CMD" >> $DCM_RFC_LOG_FILE
        result= eval $CURL_CMD > $HTTP_CODE
        ret=$?
        sleep 2
        http_code=$(awk -F\" '{print $1}' $HTTP_CODE)
        echo_t "ret = $ret http_code: $http_code" >> $DCM_RFC_LOG_FILE
        
        # Retry for STBs hosted in open internet
        if [ ! -z "$CODEBIG_ENABLED" -a "$CODEBIG_ENABLED"!=" " -a $http_code -eq 000 ] && [ -f /usr/bin/configparamgen ]; then
            echo_t "Retry attempt to Xconf dcm rfc end point using CODEBIG " >> $DCM_RFC_LOG_FILE

            SIGN_CMD="configparamgen 8 \"$JSONSTR\""
            eval $SIGN_CMD > /tmp/.signedRFCRequest
            CB_SIGNED_REQUEST=`cat /tmp/.signedRFCRequest`
            rm -f /tmp/.signedRFCRequest
            SIGN_CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' --interface $EROUTER_INTERFACE --connect-timeout $timeout -m $timeout -o  \"$DCMRFCRESPONSE\" \"$CB_SIGNED_REQUEST\""
            result= eval $SIGN_CURL_CMD > $HTTP_CODE
            ret=$?
            http_code=$(awk -F\" '{print $1}' $HTTP_CODE)
            echo_t "ret = $ret http_code: $http_code" >> $DCM_RFC_LOG_FILE
        fi
        
        if [ $http_code -eq 200 ]; then
            echo_t "Curl success" >> $DCM_RFC_LOG_FILE
            if [ -e /usr/bin/dcmjsonparser ]; then
                echo_t "dcmjsonparser binary present" >> $DCM_RFC_LOG_FILE
                /usr/bin/dcmjsonparser $DCMRFCRESPONSE 

                if [ -f $DCM_PARSER_RESPONSE ]; then 
                    echo_t "$DCM_PARSER_RESPONSE file is present" >> $DCM_RFC_LOG_FILE
                    file=$DCM_PARSER_RESPONSE
                    while read line; do
                        key=`echo $line|cut -d ":" -f1`
                        value=`echo $line|cut -d ":" -f2`
                        echo_t "key=$key value=$value" >> $DCM_RFC_LOG_FILE
                        parseConfigValue $key $value     
                    done < $file
                else
                    echo_t "$DCM_PARSER_RESPONSE is not present" >> $DCM_RFC_LOG_FILE  
                fi
            else
                echo_t "binary dcmjsonparse is not present" >> $DCM_RFC_LOG_FILE
            fi
            break    
        else
            echo_t "Curl request for DCM RFC failed" >> $DCM_RFC_LOG_FILE
        fi
   retries=`expr $retries + 1`
   sleep 10
   done
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
            #dmcli SET
            paramSet=`$SET $paramName $paramType $configValue | grep succeed| tr -s ' ' `
            if [ -n "$paramSet" ]; then
                echo_t "dmcli SET success for $paramName with value $configValue" >> $DCM_RFC_LOG_FILE
            else
                echo_t "dmcli SET failed for $paramName with value $configValue" >> $DCM_RFC_LOG_FILE
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

