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
# Script responsible for log upload based on protocol

#source /etc/utopia/service.d/log_env_var.sh
#source /etc/utopia/service.d/log_capture_path.sh

source /lib/rdk/t2Shared_api.sh

RDK_LOGGER_PATH="/rdklogger"

NVRAM2_SUPPORTED="no"
. /lib/rdk/utils.sh 
. $RDK_LOGGER_PATH/logfiles.sh

UPLOAD_LOGS=`sysevent get UPLOAD_LOGS_VAL_DCM`

if [ "$UPLOAD_LOGS" = "" ] || [ ! -f "$DCM_SETTINGS_PARSED" ]
then
    echo_t "processDCMResponse to get the logUploadSettings"
    UPLOAD_LOGS=`processDCMResponse`
fi

echo_t "UPLOAD_LOGS val is $UPLOAD_LOGS"

if [ "$UPLOAD_LOGS" = "true" ] || [ "$UPLOAD_LOGS" = "" ]
then
   echo_t "Log upload is enabled"
else
   echo_t "Log upload is disabled"
   exit 1
fi

SIGN_FILE="/tmp/.signedRequest_$$_`date +'%s'`"
CODEBIG_BLOCK_TIME=1800
CODEBIG_BLOCK_FILENAME="/tmp/.lastcodebigfail_upl"

DIRECT_MAX_ATTEMPTS=3
CODEBIG_MAX_ATTEMPTS=3

#to support ocsp
EnableOCSPStapling="/tmp/.EnableOCSPStapling"
EnableOCSP="/tmp/.EnableOCSPCA"

if [ -f $EnableOCSPStapling ] || [ -f $EnableOCSP ]; then
    CERT_STATUS="--cert-status"
fi

UseCodeBig=0
conn_str="Direct"
CodebigAvailable=0
XPKI_MTLS_MAX_TRIES=0
xpkiMtlsRFC=`syscfg get UseXPKI_Enable`
mTlsLogUpload=`syscfg get mTlsLogUpload_Enable`
encryptionEnable=`dmcli eRT getv Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.EncryptCloudUpload.Enable | grep value | cut -d ":" -f 3 | tr -d ' '`
URLENCODE_STRING=""

checkXpkiMtlsBasedLogUpload()
{
    if [ "x$xpkiMtlsRFC" = "xtrue" ] && [ -f /usr/bin/rdkssacli ] && [ -f /nvram/certs/devicecert_1.pk12 ]; then
        useXpkiMtlsLogupload="true"
        XPKI_MTLS_MAX_TRIES=2
    else
        useXpkiMtlsLogupload="false"
        XPKI_MTLS_MAX_TRIES=0
    fi
}

checkRdkCaMtlsBasedLogUpload()
{
    if [ "x$mTlsLogUpload" = "xtrue" ] && [ -f /etc/ssl/certs/cpe-clnt.xcal.tv.cert.pem ] && [ -x /usr/bin/GetConfigFile ]; then
        ID="/tmp/uydrgopwxyem"
        GetConfigFile $ID
        if [ ! -f "$ID" ]; then
            echo_t "Getconfig file fails , use standard TLS"
            useRdkCaMtlsLogupload="false"
        else
            useRdkCaMtlsLogupload="true"
        fi
    fi
}

if [ $# -lt 4 ]; then 
     echo "USAGE: $0 <TFTP Server IP> <UploadProtocol> <UploadHttpLink> <uploadOnReboot>"
     #echo "USAGE: $0 $1 $2 $3 $4"
fi
echo_t "The parameters are - arg1:$1 arg2:$2 arg3:$3 arg4:$4 arg5:$5 arg6:$6"

if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
   export PATH=$PATH:/fss/gw/
   CURL_BIN="curl"
else
   CURL_BIN=/fss/gw/curl
fi

# assign the input arguments

UploadProtocol=$2
UploadHttpLink=$3
UploadOnReboot=$4

if [ "$5" != "" ]; then
	nvram2Backup=$5
else
    backupenabled=`syscfg get logbackup_enable`
    #nvram2Supported="no"
 #   if [ -f /etc/device.properties ]
  #  then
  #     nvram2Supported=`cat /etc/device.properties | grep NVRAM2_SUPPORTED | cut -f2 -d=`
  #  fi

    if [ "$NVRAM2_SUPPORTED" = "yes" ] && [ "$backupenabled" = "true" ]
    then
       nvram2Backup="true"
    else
       nvram2Backup="false"
    fi
fi

UploadPath=$6

SECONDV=`dmcli eRT getv Device.X_CISCO_COM_CableModem.TimeOffset | grep value | cut -d ":" -f 3 | tr -d ' ' `


getFWVersion()
{
    verStr=`grep ^imagename: /version.txt | cut -d ":" -f 2`
	echo $verStr
}

getBuildType()
{
        # Currenlty this function not used. If used please ensure, calling get_Codebigconfig before this call
        # get_Codebigconfig currenlty called in HttpLogUpload 
        IMAGENAME=`grep ^imagename: /fss/gw/version.txt | cut -d ":" -f 2`

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

if [ "$UploadHttpLink" == "" ]
then
	UploadHttpLink=$URL
fi

# initialize the variables
MAC=`getMacAddressOnly`
HOST_IP=`getIPAddress`
dt=`date "+%m-%d-%y-%I-%M%p"`
LOG_FILE=$MAC"_Logs_$dt.tgz"
CM_INTERFACE="wan0"
WAN_INTERFACE="erouter0"
CURLPATH="/fss/gw"

VERSION="/fss/gw/version.txt"

http_code=0
OutputFile='/tmp/httpresult.txt'

# Function which will upload logs to TFTP server

retryUpload()
{
	while : ; do
	   sleep 10
	   WAN_STATE=`sysevent get wan_service-status`
if [ "x$BOX_TYPE" = "xHUB4" ]; then
   CURRENT_WAN_IPV6_STATUS=`sysevent get ipv6_connection_state`
   if [ "xup" = "x$CURRENT_WAN_IPV6_STATUS" ] ; then
           EROUTER_IP=`ifconfig $HUB4_IPV6_INTERFACE | grep Global |  awk '/inet6/{print $3}' | cut -d '/' -f1 | head -n1`
   else
           EROUTER_IP=`ifconfig $WAN_INTERFACE | grep "inet addr" | cut -d":" -f2 | cut -d" " -f1`
   fi
else
       EROUTER_IP=`ifconfig $WAN_INTERFACE | grep "inet addr" | cut -d":" -f2 | cut -d" " -f1`
fi
       SYSEVENT_PID=`pidof syseventd`
	   if [ -f $WAITINGFORUPLOAD ]
	   then
		   if [ "$WAN_STATE" == "started" ] && [ "$EROUTER_IP" != "" ]
		   then
			touch $REGULAR_UPLOAD
			HttpLogUpload
			rm $REGULAR_UPLOAD
			rm $WAITINGFORUPLOAD

  		   elif [ "$EROUTER_IP" != "" ] && [ "$SYSEVENT_PID" == "" ]
		   then
			touch $REGULAR_UPLOAD
			HttpLogUpload
			rm $REGULAR_UPLOAD
			rm $WAITINGFORUPLOAD
		   fi
	   else
		break
	   fi
	done
		
}

IsCodebigBlocked()
{
    ret=0
    if [ -f $CODEBIG_BLOCK_FILENAME ]; then
        modtime=$(($(date +%s) - $(date +%s -r $CODEBIG_BLOCK_FILENAME)))
        if [ "$modtime" -le "$CODEBIG_BLOCK_TIME" ]; then
            echo "Last Codebig failed blocking is still valid, preventing Codebig"
            ret=1
        else
            echo "Last Codebig failed blocking has expired, removing $CODEBIG_BLOCK_FILENAME, allowing Codebig"
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
   if [ "$CodebigAvailable" -eq "1" ] && [ "x$CodeBigEnable" != "x" ] ; then
      UseCodeBig=1 
      conn_str="Codebig"
   fi

   if [ "$CodebigAvailable" -eq "1" ]; then
      echo_t "Using $conn_str connection as the Primary"
   else
      echo_t "Only $conn_str connection is available"
   fi
}


# Direct connection Download function
useDirectRequest()
{
    # Direct Communication
    # Performing DIRECT_MAX_ATTEMPTS tries for successful curl command execution.
    # $http_code --> Response code retrieved from HTTP_CODE file path.
    echo_t "Trying Direct Communication"
    retries=0

    checkXpkiMtlsBasedLogUpload
    checkRdkCaMtlsBasedLogUpload

    if [ "x$useRdkCaMtlsLogupload" = "xtrue" ] || [ "x$useXpkiMtlsLogupload" = "xtrue" ]; then
        S3_SECURE_URL=`echo $S3_URL | sed "s|/cgi-bin|/secure&|g"`
        echo_t "Log Upload: requires Mutual Authentication. S3 Secure Url is :$S3_SECURE_URL"
    fi

    while [ "$retries" -lt "$DIRECT_MAX_ATTEMPTS" ]
    do
        echo_t "Trial $retries for DIRECT ..."
        # nice value can be normal as the first trial failed
        if [ "x$useXpkiMtlsLogupload" = "xtrue" ] && [ "$retries" -lt "$XPKI_MTLS_MAX_TRIES" ]; then
          msg_tls_source="mTLS certificate from xPKI"
          echo_t "Log Upload: $msg_tls_source"
          CURL_CMD="$CURL_BIN --tlsv1.2 --cert-type P12 --cert /nvram/certs/devicecert_1.pk12:$(/usr/bin/rdkssacli "{STOR=GET,SRC=kquhqtoczcbx,DST=/dev/stdout}") -w '%{http_code}\n' -d \"filename=$UploadFile\" $URLENCODE_STRING -o \"$OutputFile\"  --interface $WAN_INTERFACE $addr_type \"$S3_SECURE_URL\" $CERT_STATUS --connect-timeout 30 -m 30"
        elif [ "x$useRdkCaMtlsLogupload" = "xtrue" ]; then
          msg_tls_source="mTLS certificate from RDK-CA"
          echo_t "Log Upload: $msg_tls_source"
          CURL_CMD="$CURL_BIN --tlsv1.2 --key $ID --cert /etc/ssl/certs/cpe-clnt.xcal.tv.cert.pem -w '%{http_code}\n' -d \"filename=$UploadFile\" $URLENCODE_STRING -o \"$OutputFile\"  --interface $WAN_INTERFACE $addr_type \"$S3_SECURE_URL\" $CERT_STATUS --connect-timeout 30 -m 30"
        else
          msg_tls_source="TLS"
          CURL_CMD="$CURL_BIN --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" $URLENCODE_STRING -o \"$OutputFile\" --interface $WAN_INTERFACE $addr_type \"$S3_URL\" $CERT_STATUS --connect-timeout 30 -m 30"
        fi

        if [[ ! -e $UploadFile ]]; then
          echo_t "No file exist or already uploaded!!!"
          break;
        fi
        echo_t "CURL_CMD: `echo "$CURL_CMD" | sed -e 's#devicecert_1.*-w#devicecert_1.pk12<hidden key> -w#g' -e 's#AWSAccessKeyId=.*Signature=.*&#<hidden key>#g'`"
        HTTP_CODE=`ret= eval $CURL_CMD`
        if [ "x$HTTP_CODE" != "x" ]; then
            http_code=$(echo "$HTTP_CODE" | awk '{print $0}' )
            echo_t "Log Upload: $msg_tls_source Direct Communication - ret:$ret, http_code:$http_code"
            if [ "$http_code" != "" ];then
                echo_t "Log Upload: $msg_tls_source Direct connection HttpCode received is : $http_code"
                if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] ;then
                    rm -f "$ID"
                    return 0
                fi
            fi
        else
            http_code=0
            echo_t "Log Upload: $msg_tls_source Direct Communication Failure Attempt:$retries - ret:$ret, http_code:$http_code"
        fi
               
        retries=`expr $retries + 1`
        sleep 30
    done
    rm -f "$ID"
    echo_t "Retries for Direct connection exceeded " 
    return 1
}

# Codebig connection Download function        
useCodebigRequest()
{
    # Do not try Codebig if CodebigAvailable != 1 (GetServiceUrl not there)
    if [ "$CodebigAvailable" = "0" ] ; then
        echo "Log Upload : Only direct connection Available" 
        return 1
    fi

    IsCodebigBlocked
    if [ "$?" = "1" ]; then
           return 1
    fi

    echo_t "Trying Codebig Communication"


    if [ "$S3_MD5SUM" != "" ]; then
        uploadfile_md5="&md5=$S3_MD5SUM"
    fi

    retries=0
    while [ "$retries" -lt "$CODEBIG_MAX_ATTEMPTS" ]
    do
        SIGN_CMD="GetServiceUrl 1 \"/cgi-bin/rdkb.cgi?filename=$UploadFile$uploadfile_md5\""
        eval $SIGN_CMD > $SIGN_FILE
        if [ -s $SIGN_FILE ]
        then
            echo "Log upload - GetServiceUrl success"
        else
            echo "Log upload - GetServiceUrl failed"
            exit 1
        fi

        CB_SIGNED=`cat $SIGN_FILE`
        rm -f $SIGN_FILE
        S3_URL_SIGN=`echo $CB_SIGNED | sed -e "s|?.*||g"`
        echo "serverUrl : $S3_URL_SIGN"
        authorizationHeader=`echo $CB_SIGNED | sed -e "s|&|\", |g" -e "s|=|=\"|g" -e "s|.*filename|filename|g"`
        authorizationHeader="Authorization: OAuth realm=\"\", $authorizationHeader\""

        CURL_CMD="$CURL_BIN --tlsv1.2 $CERT_STATUS --connect-timeout 30 --interface $WAN_INTERFACE $addr_type -H '$authorizationHeader' -w '%{http_code}\n' $URLENCODE_STRING -o \"$OutputFile\" -d \"filename=$UploadFile\" '$S3_URL_SIGN'"
            #Sensitive info like Authorization signature should not print
        CURL_CMD_FOR_ECHO="$CURL_BIN --tlsv1.2 $CERT_STATUS --connect-timeout 30 --interface $WAN_INTERFACE $addr_type -H <Hidden authorization-header> -w '%{http_code}\n' $URLENCODE_STRING -o \"$OutputFile\" -d \"filename=$UploadFile\" '$S3_URL_SIGN'"

        echo_t "File to be uploaded: $UploadFile"
        UPTIME=`uptime`
        echo_t "System Uptime is $UPTIME"
        echo_t "S3 URL is : $S3_URL_SIGN"

        # Performing 3 tries for successful curl command execution.
        # $http_code --> Response code retrieved from HTTP_CODE file path.
        if [[ ! -e $UploadFile ]]; then
             echo_t "No file exist or already uploaded!!!"
             http_code=-1
             return 1
        fi
        echo_t "Trial $retries for CODEBIG..."
        #Sensitive info like Authorization signature should not print
        echo "Curl Command built: $CURL_CMD_FOR_ECHO"
        HTTP_CODE=`ret= eval $CURL_CMD`

        if [ "x$HTTP_CODE" != "x" ];
        then
            http_code=$(echo "$HTTP_CODE" | awk '{print $0}' )
            echo_t "Codebig Communication - ret:$ret, http_code:$http_code"

            if [ "$http_code" != "" ];then
                echo_t "Codebig connection HttpCode received is : $http_code"
                if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] ;then
                    return 0
                fi
            fi
        else
            http_code=0
            echo_t "Codebig Communication Failure Attempt:$retries - ret:$ret, http_code:$http_code"
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
    echo "Retries for Codebig connection exceeded "
    [ -f $CODEBIG_BLOCK_FILENAME ] || touch $CODEBIG_BLOCK_FILENAME
    return 1
}

# Function which will upload logs to HTTP S3 server
HttpLogUpload()
{   

    # If interface doesnt have ipv6 address then we will force the curl to go with ipv4.
    # Otherwise we will not specify the ip address family in curl options
    addr_type=""
    if [ "x$BOX_TYPE" = "xHUB4" ]; then
    CURRENT_WAN_IPV6_STATUS=`sysevent get ipv6_connection_state`
       if [ "xup" = "x$CURRENT_WAN_IPV6_STATUS" ] ; then
          [ "x`ifconfig $HUB4_IPV6_INTERFACE | grep Global |  awk '/inet6/{print $3}' | cut -d '/' -f1 | head -n1`" != "x" ] || addr_type="-4"
       else
          [ "x`ifconfig $WAN_INTERFACE | grep inet6 | grep -i 'Global'`" != "x" ] || addr_type="-4"
       fi
    else
       [ "x`ifconfig $WAN_INTERFACE | grep inet6 | grep -i 'Global'`" != "x" ] || addr_type="-4"
    fi
    # Upload logs to "LOG_BACK_UP_REBOOT" upon reboot else to the default path "LOG_BACK_UP_PATH"	
	if [ "$UploadOnReboot" == "true" ]; then
		if [ "$nvram2Backup" == "true" ]; then
			cd $LOG_SYNC_BACK_UP_REBOOT_PATH
		else
			cd $LOG_BACK_UP_REBOOT
		fi
	else
		if [ "$nvram2Backup" == "true" ]; then
			cd $LOG_SYNC_BACK_UP_PATH
		else
			cd $LOG_BACK_UP_PATH
		fi
	fi

	if [ "$UploadPath" != "" ] && [ -d $UploadPath ]; then
		FILE_NAME=`ls $UploadPath | grep "tgz"`
		if [ "$FILE_NAME" != "" ]; then
			cd $UploadPath
		fi
	fi
 
   UploadFile=`ls | grep "tgz"`
 
   # This check is to handle migration scenario from /nvram to /nvram2
   if [ "$UploadFile" = "" ] && [ "$nvram2Backup" = "true" ]
   then
       echo_t "Checking if any file available in $LOG_BACK_UP_REBOOT"
       if [ -d $LOG_BACK_UP_REBOOT ]; then
          UploadFile=`ls $LOG_BACK_UP_REBOOT | grep tgz`
       fi
       if [ "$UploadFile" != "" ]
       then
         cd $LOG_BACK_UP_REBOOT
       fi
   fi
   echo_t "files to be uploaded is : $UploadFile"
   url=`grep 'LogUploadSettings:UploadRepository:URL' /tmp/DCMresponse.txt`
   if [ "$url" != "" ]; then
       httplink=`echo $url | cut -d '"' -f4`
       if [ -z "$httplink" ]; then
           echo "`/bin/timestamp` 'LogUploadSettings:UploadRepository:URL' is not found in DCMSettings.conf, upload_httplink is '$UploadHttpLink'"
       else
           echo "LogUploadSettings $httplink"
           UploadHttpLink=$httplink
       fi
   fi
   
    S3_URL=$UploadHttpLink
    file_list=$UploadFile

    get_Codebigconfig
    for UploadFile in $file_list
    do
        echo_t "Upload file is : $UploadFile"
#        CURL_CMD="nice -n 20 $CURL_BIN --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" --interface $WAN_INTERFACE $addr_type \"$S3_URL\" --connect-timeout 30 -m 30"

        echo_t "File to be uploaded: $UploadFile"
        UPTIME=`uptime`
        echo_t "System Uptime is $UPTIME"
        echo_t "S3 URL is : $S3_URL"

        S3_MD5SUM=""
        echo "RFC_EncryptCloudUpload_Enable:$encryptionEnable"
        if [ "$encryptionEnable" == "true" ]; then
            S3_MD5SUM="$(openssl md5 -binary < $UploadFile | openssl enc -base64)"
            URLENCODE_STRING="--data-urlencode \"md5=$S3_MD5SUM\""
        fi

        if [ "$UseCodeBig" -eq "1" ]; then
           useCodebigRequest
           ret=$?
        else
           useDirectRequest
           ret=$?
        fi

        if [ "$ret" -ne "0" ] && [ "$http_code" -ne "-1" ]; then
            echo_t "INVALID RETURN CODE: $http_code"
            echo_t "LOG UPLOAD UNSUCCESSFUL TO S3"
            t2CountNotify "SYS_ERROR_LOGUPLOAD_FAILED"
            preserveThisLog $UploadFile $UploadPath
            continue
        fi

        # If 200, executing second curl command with the public key.
        if [ "$http_code" = "200" ];then
            #This means we have received the key to which we need to curl again in order to upload the file.
            #So get the key from FILENAME
            Key=$(awk -F\" '{print $0}' $OutputFile)

            # if url uses http, then log and force https (RDKB-13142)
            echo "$Key" | tr '[:upper:]' '[:lower:]' | grep -q -e 'http://'
            if [ "$?" = "0" ]; then
                echo_t "LOG UPLOAD TO S3 requested http. Forcing to https"
                Key=$(echo "$Key" | sed -e 's#http://#https://#g' -e 's#:80/#:443/#')
                forced_https="true"
            else
                forced_https="false"
            fi

            #RDKB-14283 Remove Signature from CURL command in consolelog.txt and ArmConsolelog.txt
            RemSignature=`echo $Key | sed "s/AWSAccessKeyId=.*Signature=.*&//g;s/\"//g;s/.*https/https/g"`
            if [ "$encryptionEnable" != "true" ]; then
                Key=\"$Key\"
            fi
            echo_t "Generated KeyIs : "
            echo $RemSignature

            if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
                CURL_CMD="nice -n 20 curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE $Key $CERT_STATUS --connect-timeout 30 -m 30"
		#Sensitive info like Authorization signature should not print
                CURL_CMD_FOR_ECHO="nice -n 20 curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"$RemSignature\" $CERT_STATUS --connect-timeout 30 -m 30"
            else
                CURL_CMD="nice -n 20 /fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE $Key $CERT_STATUS --connect-timeout 30 -m 30"
		#Sensitive info like Authorization signature should not print
                CURL_CMD_FOR_ECHO="nice -n 20 /fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"$RemSignature\" $CERT_STATUS --connect-timeout 30 -m 30"
            fi

            retries=0
            while [ "$retries" -lt "3" ]
            do
                echo_t "Trial $retries..."
                # nice value can be normal as the first trial failed
                if [ $retries -ne 0 ]; then
                    if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
                        CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE $Key $CERT_STATUS --connect-timeout 30 -m 30"
			#Sensitive info like Authorization signature should not print
                        CURL_CMD_FOR_ECHO="curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"$RemSignature\" $CERT_STATUS --connect-timeout 30 -m 30"
                    else
                        CURL_CMD="/fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE $Key $CERT_STATUS --connect-timeout 30 -m 30"
			#Sensitive info like Authorization signature should not print
                        CURL_CMD_FOR_ECHO="/fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"$RemSignature\" $CERT_STATUS --connect-timeout 30 -m 30"
                    fi
                fi
	            if [[ ! -e $UploadFile ]]; then
                   echo_t "No file exist or already uploaded!!!"
                   http_code=-1
                   break
                fi
                #Sensitive info like Authorization signature should not print
                echo_t "Curl Command built: $CURL_CMD_FOR_ECHO"
                eval $CURL_CMD > $HTTP_CODE
                ret=$?

                #Check for forced https security failure
                if [ "$forced_https" = "true" ]; then
                    case $ret in
                        35|51|53|54|58|59|60|64|66|77|80|82|83|90|91)
                            echo_t "LOG UPLOAD TO S3 forced https failed"
                    esac
                fi

                if [ -f $HTTP_CODE ]; then
                    http_code=$(awk '{print $0}' $HTTP_CODE)

                    if [ "$http_code" != "" ];then
                        echo_t "HttpCode received is : $http_code"
                        if [ "$http_code" = "200" ];then
                            break
                        fi
                    fi
                else
                    http_code=0
                fi

                retries=`expr $retries + 1`
                sleep 30
            done

            # Response after executing curl with the public key is 200, then file uploaded successfully.
            if [ "$http_code" = "200" ];then
                echo_t "LOGS UPLOADED SUCCESSFULLY, RETURN CODE: $http_code"
		t2CountNotify "SYS_INFO_LOGS_UPLOADED"
                rm -rf $UploadFile
		if [ -f "$PRESERVE_LOG_PATH/$UploadFile" ] && [ "$UploadPath" != "$PRESERVE_LOG_PATH" ]; then #Remove from backup.
		   rm -rf "$PRESERVE_LOG_PATH/$UploadFile"
		   adjustPreserveCount
		fi
                #Venu ARRISXB6-8244 
                if [ "$UploadPath" = "$PRESERVE_LOG_PATH" ] ; then
                   adjustPreserveCount
                fi

	        else
                 if [ "$http_code" -ne "-1" ]; then
                    echo_t "LOGS UPLOAD FAILED, RETURN CODE: $http_code"
                    preserveThisLog $UploadFile $UploadPath
                fi
            fi

        #When 302, there is URL redirection.So get the new url from FILENAME and curl to it to get the key.
        elif [ "$http_code" = "302" ];then
            NewUrl=$(grep -oP "(?<=HREF=\")[^\"]+(?=\")" $OutputFile)

            # if url uses http, then log and force https (RDKB-13142)
            echo "$NewUrl" | tr '[:upper:]' '[:lower:]' | grep -q -e 'http://'
            if [ "$?" = "0" ]; then
                echo_t "LOG UPLOAD TO S3 requested http. Forcing to https"
                NewUrl=$(echo "$NewUrl" | sed -e 's#http://#https://#g' -e 's#:80/#:443/#')
                forced_https="true"
            else
                forced_https="false"
            fi

            CURL_CMD="nice -n 20 $CURL_BIN --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" \"$NewUrl\" --interface $WAN_INTERFACE $addr_type $CERT_STATUS --connect-timeout 30 -m 30"

            retries=0
            while [ "$retries" -lt "3" ]
            do
                echo_t "Trial $retries..."
                # nice value can be normal as the first trial failed
                if [ $retries -ne 0 ]; then
                     CURL_CMD="$CURL_BIN --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" $URLENCODE_STRING -o \"$OutputFile\" --interface $WAN_INTERFACE $addr_type \"$S3_URL\" $CERT_STATUS --connect-timeout 30 -m 30"
                fi
                if [[ ! -e $UploadFile ]]; then
                   echo_t "No file exist or already uploaded!!!"
                   http_code=-1
                   break
               fi
                echo_t "Curl Command built: $CURL_CMD"
                eval $CURL_CMD > $HTTP_CODE
                ret=$?

                #Check for forced https security failure
                if [ "$forced_https" = "true" ]; then
                    case $ret in
                        35|51|53|54|58|59|60|64|66|77|80|82|83|90|91)
                            echo_t "LOG UPLOAD TO S3 forced https failed"
                    esac
                fi

                echo_t "Curl Command built: `echo "$CURL_CMD" | sed -e 's#devicecert_1.*-w#devicecert_1.pk12<hidden key> -w#g' -e 's#AWSAccessKeyId=.*Signature=.*&#<hidden key>#g'`"
                ret= eval $CURL_CMD > $HTTP_CODE
                if [ -f $HTTP_CODE ]; then
                    http_code=$(awk '{print $0}' $HTTP_CODE)
                    if [ "$http_code" != "" ];then
                        echo_t "HttpCode received is : $http_code"
                        if [ "$http_code" = "200" ];then
                            break
                        fi
                    fi
                else
                    http_code=0
                fi
                retries=`expr $retries + 1`
                sleep 30
            done



            #Executing curl with the response key when return code after the first curl execution is 200.
            if [ "$http_code" = "200" ];then
                Key=$(awk '{print $0}' $OutputFile)
	        #RDKB-14283 Remove Signature from CURL command in consolelog.txt and ArmConsolelog.txt
                RemSignature=`echo $Key | sed "s/AWSAccessKeyId=.*Signature=.*&//g;s/\"//g;s/.*https/https/g"`
                if [ "$encryptionEnable" != "true" ]; then
                    Key=\"$Key\"
                fi
                CURL_CMD="nice -n 20 $CURL_BIN --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE $addr_type $Key $CERT_STATUS --connect-timeout 10 -m 10"
                #Sensitive info like Authorization signature should not print
                CURL_CMD_FOR_ECHO="nice -n 20 $CURL_BIN --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE $addr_type \"$RemSignature\" $CERT_STATUS --connect-timeout 10 -m 10"

                retries=0
                while [ "$retries" -lt "3" ]
                do
                    echo_t "Trial $retries..."
                    # nice value can be normal as the first trial failed
                    if [ $retries -ne 0 ]; then
                        CURL_CMD="$CURL_BIN --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE $addr_type  $Key $CERT_STATUS --connect-timeout 10 -m 10"
                            #Sensitive info like Authorization signature should not print
                        CURL_CMD_FOR_ECHO="$CURL_BIN --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE $addr_type \"$RemSignature\" $CERT_STATUS --connect-timeout 10 -m 10"
                    fi
                    if [[ ! -e $UploadFile ]]; then
                       echo_t "No file exist or already uploaded!!!"
                       http_code=-1
                       break
		            fi
		    #Sensitive info like Authorization signature should not print
                    echo_t "Curl Command built: $CURL_CMD_FOR_ECHO"
                    HTTP_CODE=`ret= eval $CURL_CMD`
                    if [ "x$HTTP_CODE" != "x" ]; then
                        http_code=$(echo "$HTTP_CODE" | awk '{print $0}' )

                        if [ "$http_code" != "" ];then

                            if [ "$http_code" = "200" ];then
                                break
                            fi
                        fi
                    else
                        http_code=0
                    fi
                    retries=`expr $retries + 1`
                    sleep 30
                done
                #Logs upload successful when the return code is 200 after the second curl execution.
                if [ "$http_code" = "200" ];then
                    echo_t "LOGS UPLOADED SUCCESSFULLY, RETURN CODE: $http_code"
		    t2CountNotify "SYS_INFO_LOGS_UPLOADED"
                    result=0
                    rm -rf $UploadFile
                    if [ -f "$PRESERVE_LOG_PATH/$UploadFile" ] && [ "$UploadPath" != "$PRESERVE_LOG_PATH" ]; then #Remove from backup.
                      rm -rf "$PRESERVE_LOG_PATH/$UploadFile"
                      adjustPreserveCount
                    fi
                    #Venu ARRISXB6-8244 
                    if [ "$UploadPath" = "$PRESERVE_LOG_PATH" ] ; then
                      adjustPreserveCount
                    fi
                else
                    if [ "$http_code" -ne "-1" ]; then
                        echo_t "LOG UPLOAD FAILED, RETURN CODE: $http_code"
                        preserveThisLog $UploadFile $UploadPath
                    fi
                fi
            fi
        else
            if [ "$http_code" -ne "-1" ]; then
                echo_t "INVALID RETURN CODE: $http_code"
                echo_t "LOG UPLOAD UNSUCCESSFUL TO S3"
                t2CountNotify "SYS_ERROR_LOGUPLOAD_FAILED"
                preserveThisLog $UploadFile $UploadPath
            fi

            fi

        echo_t $result
    done

    #Venu ARRISXB6-8244 
    if [ "$UploadPath" != "$PRESERVE_LOG_PATH" ] ; then
      if [ "$UploadPath" != "" ] && [ -d $UploadPath ]; then
        rm -rf $UploadPath
      fi
    fi
        
}

#Function to preserve log in case of WAN down
PreserveLog()
{
        if [ "$UploadPath" != "" ] && [ -d $UploadPath ]; then
                file_list=`ls -tr $UploadPath | grep "tgz"`
                if [ "$file_list" != "" ]; then
        		for UploadFile in $file_list
        		do
                		preserveThisLog $UploadFile $UploadPath #preserve oldest log
                		break
		        done
                fi
        fi
}

# Flag that a log upload is in progress. 
if [ -e $REGULAR_UPLOAD ]
then
	rm $REGULAR_UPLOAD
fi

if [ -f $WAITINGFORUPLOAD ]
then
	rm -rf $WAITINGFORUPLOAD
fi

touch $REGULAR_UPLOAD

#Check the protocol through which logs need to be uploaded
if [ "$UploadProtocol" = "HTTP" ]
then
   WAN_STATE=`sysevent get wan_service-status`
if [ "x$BOX_TYPE" = "xHUB4" ]; then
   CURRENT_WAN_IPV6_STATUS=`sysevent get ipv6_connection_state`
   if [ "xup" = "x$CURRENT_WAN_IPV6_STATUS" ] ; then
           EROUTER_IP=`ifconfig $HUB4_IPV6_INTERFACE | grep Global |  awk '/inet6/{print $3}' | cut -d '/' -f1 | head -n1`
   else
           EROUTER_IP=`ifconfig $WAN_INTERFACE | grep "inet addr" | cut -d":" -f2 | cut -d" " -f1`
   fi
else
   EROUTER_IP=`ifconfig $WAN_INTERFACE | grep "inet addr" | cut -d":" -f2 | cut -d" " -f1`
fi
   SYSEVENT_PID=`pidof syseventd`
   if [ "$WAN_STATE" == "started" ] && [ "$EROUTER_IP" != "" ]
   then
	   echo_t "Upload HTTP_LOGS"
	   HttpLogUpload
   elif [ "$EROUTER_IP" != "" ] && [ "$SYSEVENT_PID" == "" ]
   then
	   echo_t "syseventd is crashed, $WAN_INTERFACE has IP Uploading HTTP_LOGS"
	   HttpLogUpload
   else
	   echo_t "WAN is down, waiting for Upload LOGS"
	   PreserveLog	#Preserve oldest log if WAN is down, then retry to upload
	   touch $WAITINGFORUPLOAD
	   retryUpload &
   fi
fi

# Remove the log in progress flag
if [ -f $REGULAR_UPLOAD ]
then
    rm $REGULAR_UPLOAD
fi
# removing event which is set in backupLogs.sh when wan goes down
sysevent set wan_event_log_upload no
