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

# Usage : ./onboardLogUpload.sh "upload" <file_to_upload>
# Arguments:
#	upload - This will trigger an upload of <file_to_upload>
#
#
#

source  /etc/log_timestamp.sh

if [ -f /etc/ONBOARD_LOGGING_ENABLE ]; then
    ONBOARDLOGS_NVRAM_BACKUP_PATH="/nvram2/onboardlogs/"
    ONBOARDLOGS_TMP_BACKUP_PATH="/tmp/onboardlogs/"
fi

source /lib/rdk/t2Shared_api.sh

ARGS=$1
UploadFile=$2
blog_dir="/nvram2/onboardlogs/"

# This check is put to determine whether the image is Yocto or not
if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
   export PATH=$PATH:/fss/gw/
   CURL_BIN="curl"
else
   CURL_BIN="/fss/gw/curl"
fi

UseCodeBig=0
conn_str="Direct"
first_conn=useDirectRequest
sec_conn=useCodebigRequest
CodebigAvailable=0
encryptionEnable=`dmcli eRT getv Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.EncryptCloudUpload.Enable | grep value | cut -d ":" -f 3 | tr -d ' '`
URLENCODE_STRING=""

DIRECT_BLOCK_TIME=86400
DIRECT_BLOCK_FILENAME="/tmp/.lastdirectfail_olu"
WAN_INTERFACE="erouter0"
UploadHttpLink=$3

if [ "$UploadHttpLink" == "" ]
then
	UploadHttpLink=$URL
fi

# Get the configuration of codebig settings
get_Codebigconfig()
{
   # If GetServiceUrl not available, then only direct connection available and no fallback mechanism
   if [ -f /usr/bin/GetServiceUrl ]; then
      CodebigAvailable=1
   fi

   if [ "$CodebigAvailable" = "1" ]; then
       CodeBigEnable=`dmcli eRT getv Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.CodeBigFirst.Enable | grep true 2>/dev/null`
   fi
   if [ "$CodebigAvailable" = "1" ] && [ "x$CodeBigEnable" != "x" ] ; then
      UseCodeBig=1 
      conn_str="Codebig"
      first_conn=useCodebigRequest
      sec_conn=useDirectRequest
   fi

   if [ "$CodebigAvailable" = "1" ]; then
      echo_t "Using $conn_str connection as the Primary"
   else
      echo_t "Only $conn_str connection is available"
   fi
}

IsDirectBlocked()
{
    ret=0
    if [ -f $DIRECT_BLOCK_FILENAME ]; then
        modtime=$(($(date +%s) - $(date +%s -r $DIRECT_BLOCK_FILENAME)))
        if [ "$modtime" -le "$DIRECT_BLOCK_TIME" ]; then
            echo "Last direct failed blocking is still valid, preventing direct" 
            ret=1
        else
            echo "Last direct failed blocking has expired, removing $DIRECT_BLOCK_FILENAME, allowing direct" 
            rm -f $DIRECT_BLOCK_FILENAME
            ret=0
        fi
    fi
    return $ret
}

# Direct connection Download function
useDirectRequest()
{
    # Direct connection will not be tried if .lastdirectfail exists
    IsDirectBlocked
    if [ "$?" = "1" ]; then
       return 1
    fi
    retries=0
    while [ "$retries" -lt "3" ]
    do
        echo_t "Trying Direct Communication"
        CURL_CMD="$CURL_BIN --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" $URLENCODE_STRING -o \"$OutputFile\" \"$S3_URL\" --interface $WAN_INTERFACE $addr_type --connect-timeout 30 -m 30"

        echo_t "File to be uploaded: $UploadFile"
        UPTIME=`uptime`
        echo_t "System Uptime is $UPTIME"
        echo_t "S3 URL is : $S3_URL"

        echo_t "Trial $retries for DIRECT ..."
        #Sensitive info like Authorization signature should not print
        echo_t "Curl Command built: `echo "$CURL_CMD" | sed -ne 's#AWSAccessKeyId=.*Signature=.*&#<hidden key>#p'`"
        HTTP_CODE=`ret= eval $CURL_CMD`

        if [ "x$HTTP_CODE" != "x" ];
        then
            http_code=$(echo "$HTTP_CODE" | awk '{print $0}' )
            echo_t "Direct communication HttpCode received is : $http_code"

            if [ "$http_code" != "" ];then
                 echo_t "Direct Communication - ret:$ret, http_code:$http_code"
                 if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] ;then
			echo $http_code > $UPLOADRESULT
                        return 0
                 fi
                 echo "failed" > $UPLOADRESULT
            fi
        else
            http_code=0
            echo_t "Direct Communication Failure Attempt:$retries  - ret:$ret, http_code:$http_code"
        fi
        retries=`expr $retries + 1`
        sleep 30
    done
   echo "Retries for Direct connection exceeded " 
   [ "$CodebigAvailable" != "1" ] || [ -f $DIRECT_BLOCK_FILENAME ] || touch $DIRECT_BLOCK_FILENAME
    return 1
}

# Codebig connection Download function        
useCodebigRequest()
{
    # Do not try Codebig if CodebigAvailable != 1 (GetServiceUrl not there)
    if [ "$CodebigAvailable" = "0" ] ; then
        echo "OpsLog Upload : Only direct connection Available"
        return 1
    fi


    if [ "$S3_MD5SUM" != "" ]; then
        uploadfile_md5="&md5=$S3_MD5SUM"
    fi

    retries=0
    while [ "$retries" -lt "3" ]
    do
         echo_t "Trying Codebig Communication"
         SIGN_CMD="GetServiceUrl 1 \"/cgi-bin/rdkb.cgi?filename=$UploadFile$uploadfile_md5\""
         eval $SIGN_CMD > $SIGN_FILE
         if [ -s $SIGN_FILE ]
         then
             echo "Log upload - GetServiceUrl success"
         else
             echo "Log upload - GetServiceUrl failed"
             exit
         fi
         CB_SIGNED=`cat $SIGN_FILE`
         rm -f $SIGN_FILE
         S3_URL_SIGN=`echo $CB_SIGNED | sed -e "s|?.*||g"`
         echo "serverUrl : $S3_URL_SIGN"
         authorizationHeader=`echo $CB_SIGNED | sed -e "s|&|\", |g" -e "s|=|=\"|g" -e "s|.*filename|filename|g"`
         authorizationHeader="Authorization: OAuth realm=\"\", $authorizationHeader\""
         CURL_CMD="$CURL_BIN --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" $URLENCODE_STRING -o \"$OutputFile\" \"$S3_URL_SIGN\" --interface $WAN_INTERFACE $addr_type -H '$authorizationHeader' --connect-timeout 30 -m 30"
        echo_t "File to be uploaded: $UploadFile"
        UPTIME=`uptime`
        echo_t "System Uptime is $UPTIME"
        echo_t "S3 URL is : $S3_URL_SIGN"

        echo_t "Trial $retries for CODEBIG ..."
        #Sensitive info like Authorization signature should not print
        echo_t "Curl Command built: `echo "$CURL_CMD" | sed -ne 's#'"$authorizationHeader"'#<Hidden authorization-header>#p'` "
        HTTP_CODE=`ret= eval $CURL_CMD `

        if [ "x$HTTP_CODE" != "x" ];
        then
             http_code=$(echo "$HTTP_CODE" | awk '{print $0}' )
             echo_t "Codebig connection HttpCode received is : $http_code"

             if [ "$http_code" != "" ];then
                 echo_t "Codebig Communication - ret:$ret, http_code:$http_code"
                 if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] ;then
			echo $http_code > $UPLOADRESULT
                        return 0
                 fi
                 echo "failed" > $UPLOADRESULT
             fi
        else
             http_code=0
             echo_t "Codebig Communication Failure Attempts:$retries - ret:$ret, http_code:$http_code"
        fi

        retries=`expr $retries + 1`
        sleep 30
    done
    echo "Retries for Codebig connection exceeded "
    return 1
}

uploadOnboardLogs()
{
    curDir=`pwd`
    cd $blog_dir
    # If interface doesnt have ipv6 address then we will force the curl to go with ipv4.
    # Otherwise we will not specify the ip address family in curl options
    addr_type=""
    [ "x`ifconfig $WAN_INTERFACE | grep inet6 | grep -i 'Global'`" != "x" ] || addr_type="-4"

    S3_URL=$UploadHttpLink
    S3_MD5SUM=""
    echo "RFC_EncryptCloudUpload_Enable:$encryptionEnable"
    if [ "$encryptionEnable" == "true" ]; then
        S3_MD5SUM="$(openssl md5 -binary < $UploadFile | openssl enc -base64)"
        URLENCODE_STRING="--data-urlencode \"md5=$S3_MD5SUM\""
    fi

    $first_conn || $sec_conn || { echo "LOG UPLOAD UNSUCCESSFUL,INVALID RETURN CODE: $http_code" ; }

    # If 200, executing second curl command with the public key.
    if [ "$http_code" = "200" ];then
        #This means we have received the key to which we need to curl again in order to upload the file.
        #So get the key from FILENAME
        Key=$(awk '{print $0}' $OutputFile)
        RemSignature=`echo $Key | sed "s/AWSAccessKeyId=.*Signature=.*&//g;s/\"//g;s/.*https/https/g"`
        if [ "$encryptionEnable" != "true" ]; then
            Key=\"$Key\"
        fi
        echo_t "Generated KeyIs : "
        echo $RemSignature

        if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
           CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE $Key --connect-timeout 30 -m 30"
           CURL_CMD_FOR_ECHO="curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"$RemSignature\" --connect-timeout 30 -m 30"
        else
           CURL_CMD="/fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE $Key --connect-timeout 30 -m 30"
           CURL_CMD_FOR_ECHO="/fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"$RemSignature\" --connect-timeout 30 -m 30"
        fi
        echo_t "Curl Command built: $CURL_CMD_FOR_ECHO"

        ret= eval $CURL_CMD > $HTTP_CODE
        if [ -f $HTTP_CODE ];
        then
            http_code=$(awk '{print $0}' $HTTP_CODE)
            if [ "$http_code" != "" ];then
                echo_t "HttpCode received is : $http_code"
                if [ "$http_code" = "200" ];then
                    echo $http_code > $UPLOADRESULT
                    break
                else
                    echo "failed" > $UPLOADRESULT
                fi
            else
                http_code=0
            fi
        fi
        # Response after executing curl with the public key is 200, then file uploaded successfully.
        if [ "$http_code" = "200" ];then
	     echo_t "LOGS UPLOADED SUCCESSFULLY, RETURN CODE: $http_code"
	     t2CountNotify "LOGS_UPLOADED"
        fi
    else
        echo_t "LOG UPLOAD UNSUCCESSFUL,INVALID RETURN CODE: $http_code"
    fi
    cd $curDir
}

if [ "$ARGS" = "upload" ]
then
	# Call function to upload onboard log files
	uploadOnboardLogs
fi

if [ "$ARGS" = "delete" ]
then
    echo_t "Deleting all onboard logs from $ONBOARDLOGS_NVRAM_BACKUP_PATH and $ONBOARDLOGS_TMP_BACKUP_PATH"
    rm -rf $ONBOARDLOGS_TMP_BACKUP_PATH
    rm -rf $ONBOARDLOGS_NVRAM_BACKUP_PATH
fi
