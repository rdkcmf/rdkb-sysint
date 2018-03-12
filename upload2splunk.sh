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
. /etc/include.properties
. /etc/device.properties

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib:/usr/lib:/lib
export PATH=$PATH:/usr/sbin:/sbin:/usr/bin:/bin

TELEMETRY_PATH="$PERSISTENT_PATH/.telemetry"        #We can make use of telemetry paths
HTTP_CODE="$TELEMETRY_PATH/dca_curl_httpcode"
HTTP_FILENAME="$TELEMETRY_PATH/dca_httpresult.txt"
GET_SPLUNK_URL_PATH=/tmp/DCMresponse.txt
SPLUNK_URL_CACHE="/tmp/.splunk_end_point"

# Utility script for getting MAC address utilities
if [ -f /lib/rdk/utils.sh ];then
     . /lib/rdk/utils.sh
fi

# Check if we are using https servers
if [ -f $SPLUNK_URL_CACHE ]; then
    splunkServer=`cat $SPLUNK_URL_CACHE`
else
    if [ -f $GET_SPLUNK_URL_PATH ]; then
        splunkServer=`grep '"uploadRepository:URL":"' /tmp/DCMresponse.txt | awk -F 'uploadRepository:URL":' '{print $NF}' | awk -F '",' '{print $1}' | sed 's/"//g' | sed 's/}//g'`
        if [ ! -z "$splunkServer" ]; then
            echo "$splunkServer" > $SPLUNK_URL_CACHE
        fi
    fi
fi

echo "================ Start -> `Timestamp` ===================== "
# Samhain messages are logged to stdin
read notificationMessages

if [ -z "$notificationMessages" ]; then
    # There are no input messages
    echo "Error!!!!! No input messages ..."
    exit 0 ;
fi

# Override for automated tests in non prod builds
if [ -f $PERSISTENT_PATH/splunk.conf ] && [ $BUILD_TYPE != "prod" ] ; then
    splunkServer=`cat $PERSISTENT_PATH/splunk.conf | tr -d ' '`
fi

if [ -z "$splunkServer" ]; then
    # Empty server details !!! Add default values
    splunkServer="https://stbrtl.r53.xcal.tv"
fi

if [ -f /tmp/estb_ipv4 ]; then
   echo "$notificationMessages" | grep -i 'dibbler' > /dev/null
   if [ $? -eq 0 ]; then
       # Ignore false positive
       exit 0
   fi
fi

if [ ! -f /tmp/.standby ]; then
    echo "$notificationMessages" >> /rdklogs/logs/samhain.log
fi

# Do minimum preprocessing if required on messages to avoid
if [ "$DEVICE_TYPE" = "hybrid" ];then
      estb_mac=`ifconfig -a $EROUTER_INTERFACE | grep $EROUTER_INTERFACE | tr -s ' ' | cut -d ' ' -f5 | tr -d '\r\n' | tr '[a-z]' '[A-Z]'`
else
      estb_mac=$(getErouterMacAddress)
fi
software_version=`grep ^imagename: /version.txt | cut -d ':' -f2`

#Date may not be required as the messages already has timestamp
#datetime=`date '+%Y-%m-%d %H:%M:%S'`

strjson="{\"searchResult\":[{\"samhain\":\"2\"},{\"mac\":\"$estb_mac\"},{\"Version\":\"$software_version\"},{\"logEntry\":\"$notificationMessages\"}]}"

echo "strjson: "\'$strjson\'

CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' --interface $EROUTER_INTERFACE -H \"Accept: application/json\" -H \"Content-type: application/json\" -X POST -d '$strjson' -o \"$HTTP_FILENAME\" \"$splunkServer\" --connect-timeout 30 -m 30"

echo "CURL_CMD : $CURL_CMD"
ret= eval $CURL_CMD > $HTTP_CODE
http_code=$(awk -F\" '{print $1}' $HTTP_CODE)
echo "ret : $ret       http_code:$http_code "

echo "================ End  ===================== "

