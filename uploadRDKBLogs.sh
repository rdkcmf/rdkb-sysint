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

source /etc/utopia/service.d/log_env_var.sh
source /etc/utopia/service.d/log_capture_path.sh

. $RDK_LOGGER_PATH/utils.sh 
. $RDK_LOGGER_PATH/logfiles.sh

if [ -f /etc/device.properties ]; then
    codebig_enabled=`cat /etc/device.properties | grep CODEBIG_ENABLED | cut -f2 -d=`
fi
codebig=`dmcli eRT getv Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.CodebigSupport | grep value | cut -d ":" -f 3 | tr -d ' ' `
if [ "$codebig" == "true" ]; then
    codebig_enabled=yes
    echo "Codebig support is enabled through RFC"
fi

if [ $# -ne 4 ]; then 
     #echo "USAGE: $0 <TFTP Server IP> <UploadProtocol> <UploadHttpLink> <uploadOnReboot>"
     echo "USAGE: $0 $1 $2 $3 $4"
fi

if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
export PATH=$PATH:/fss/gw/
fi

# assign the input arguments
TFTP_SERVER=$1
UploadProtocol=$2
UploadHttpLink=$3
UploadOnReboot=$4

if [ "$5" != "" ]; then
	nvram2Backup=$5
else
    backupenabled=`syscfg get logbackup_enable`
    nvram2Supported="no"
    if [ -f /etc/device.properties ]
    then
       nvram2Supported=`cat /etc/device.properties | grep NVRAM2_SUPPORTED | cut -f2 -d=`
    fi

    if [ "$nvram2Supported" = "yes" ] && [ "$backupenabled" = "true" ]
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
	verStr=`cat /version.txt | grep ^imagename: | cut -d ":" -f 2`
	echo $verStr
}

getTFTPServer()
{
        if [ "$1" != "" ]
        then
		logserver=`cat $RDK_LOGGER_PATH/dcmlogservers.txt | grep $1 | cut -f2 -d"|"`
		echo $logserver
	fi
}

getBuildType()
{
   
	if [ "$codebig_enabled" == "yes" ]; then
		IMAGENAME=`cat /fss/gw/version.txt | grep ^imagename: | cut -d ":" -f 2`
	else
		IMAGENAME=`cat /fss/gw/version.txt | grep ^imagename= | cut -d "=" -f 2`
	fi

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
if [ "$TFTP_SERVER" == "" ]
then
	BUILD_TYPE=`getBuildType`
	TFTP_SERVER=`getTFTPServer $BUILD_TYPE`
fi

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
CA_CERT="/nvram/cacert.pem"

VERSION="/fss/gw/version.txt"

http_code=0
OutputFile='/tmp/httpresult.txt'
HTTP_CODE="/tmp/curl_httpcode"

# Function which will upload logs to TFTP server

retryUpload()
{
	while : ; do
	   sleep 10
	   WAN_STATE=`sysevent get wan_service-status`
       EROUTER_IP=`ifconfig $WAN_INTERFACE | grep "inet addr" | cut -d":" -f2 | cut -d" " -f1`
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
TFTPLogUpload()
{
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

	FILE_NAME=`ls | grep "tgz"`

        # This check is to handle migration scenario from /nvram to /nvram2
        if [ "$FILE_NAME" = "" ] && [ "$nvram2Backup" = "true" ]
        then
           echo_t "Checking if any file available in $LOG_BACK_UP_REBOOT"
           FILE_NAME=`ls $LOG_BACK_UP_REBOOT | grep tgz`
           if [ "$FILE_NAME" != "" ]
           then
               cd $LOG_BACK_UP_REBOOT
           fi
        fi
	echo_t "Log file $FILE_NAME is getting uploaded to $TFTP_SERVER..."
	#tftp -l $FILE_NAME -p $TFTP_SERVER  
# this is still insecure!
if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
	curl -T $FILE_NAME  --interface $WAN_INTERFACE tftp://$TFTP_SERVER
else
	$CURLPATH/curl -T $FILE_NAME  --interface $WAN_INTERFACE tftp://$TFTP_SERVER
fi

	sleep 3
        
        if [ "$UploadPath" != "" ] && [ -d $UploadPath ]; then
		rm -rf $UploadPath
	fi
   
}

# Function which will upload logs to HTTP S3 server
HttpLogUpload()
{   
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
       UploadFile=`ls $LOG_BACK_UP_REBOOT | grep tgz`
       if [ "$UploadFile" != "" ]
       then
         cd $LOG_BACK_UP_REBOOT
       fi
   fi
   echo_t "files to be uploaded is : $UploadFile"

    S3_URL=$UploadHttpLink
    file_list=$UploadFile

    for UploadFile in $file_list
    do
        echo_t "Upload file is : $UploadFile"
        ######################CURL COMMAND PARAMETERS##############################
        #/fss/gw/curl       --> Path to curl.
        #-w                 --> Write to console.
        #%{http_code}       --> Header response code.
        #-d                 --> HTTP POST data.
        #$UploadFile        --> File to upload.
        #-o                 --> Write output to.
        #$OutputFile        --> Output File.
        #--cacert           --> certificate to verify peer.
        #/nvram/cacert.pem  --> Certificate.
        #$S3_URL            --> Public key URL Link.
        #--connect-timeout  --> Maximum time allowed for connection in seconds.
        #-m                 --> Maximum time allowed for the transfer in seconds.
        #-T                 --> Transfer FILE given to destination.
        #--interface        --> Network interface to be used [eg:erouter1]
        ##########################################################################

        if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
           CURL_CMD="nice -n 20 curl --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" --cacert $CA_CERT --interface $WAN_INTERFACE \"$S3_URL\" --connect-timeout 30 -m 30"
        else
           CURL_CMD="nice -n 20 /fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" --cacert $CA_CERT --interface $WAN_INTERFACE \"$S3_URL\" --connect-timeout 30 -m 30"
        fi

        echo_t "File to be uploaded: $UploadFile"
        UPTIME=`uptime`
        echo_t "System Uptime is $UPTIME"
        echo_t "S3 URL is : $S3_URL"

        if [ "$codebig_enabled" != "yes" ]; then
            # Direct Communication
            # Performing 3 tries for successful curl command execution.
            # $http_code --> Response code retrieved from HTTP_CODE file path.
            echo_t "Trying Direct Communication"
            retries=0
            while [ "$retries" -lt 3 ]
            do
                echo_t "Trial $retries..."
                # nice value can be normal as the first trial failed
                if [ $retries -ne 0 ]
                then
                    if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
                        CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" --cacert $CA_CERT --interface $WAN_INTERFACE \"$S3_URL\" --connect-timeout 30 -m 30"
                    else
                        CURL_CMD="/fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" --cacert $CA_CERT --interface $WAN_INTERFACE \"$S3_URL\" --connect-timeout 30 -m 30"
                    fi
                fi
                echo_t "Curl Command built: $CURL_CMD"
                echo_t "CURL_CMD:$CURL_CMD"
                ret= eval $CURL_CMD > $HTTP_CODE

                if [ -f $HTTP_CODE ]; then
                    http_code=$(awk '{print $0}' $HTTP_CODE)
                    echo_t "Direct Communication - ret:$ret, http_code:$http_code"
                    if [ "$http_code" != "" ];then
                    echo_t "HttpCode received is : $http_code"
                        if [ $http_code -eq 200 ];then
                            rm -f $HTTP_CODE
                            break
                        fi
                    fi
                fi
               
                retries=`expr $retries + 1`
                sleep 30
            done
        else
            retries=0
            while [ "$retries" -lt 10 ]
            do
                echo "Trial $retries..."

                if [ $retries -ne 0 ]; then
                    if [ -f /nvram/adjdate.txt ]; then
                        echo -e "$0  --> /nvram/adjdate exist. It is used by another program"
                        echo -e "$0 --> Sleeping 10 seconds and try again\n"
                        else
                        echo -e "$0  --> /nvram/adjdate NOT exist. Writing date value"
                        dateString=`date +'%s'`
                        count=$(expr $dateString - $SECONDV)
                        echo "$0  --> date adjusted:"
                        date -d @$count
                        echo $count > /nvram/adjdate.txt
                        break
                    fi
                fi

                retries=`expr $retries + 1`
                sleep 10
            done
            if [ ! -f /nvram/adjdate.txt ];then
                echo "LOG UPLOAD UNSUCCESSFUL TO S3 because unable to write date info to /nvram/adjdate.txt"
                rm -rf $UploadFile
                exit
            fi
            echo_t "Trying Codebig Communication"
            retries=0
            while [ "$retries" -lt 3 ]
            do

                SIGN_CMD="configparamgen 1 \"/cgi-bin/rdkb.cgi?filename=$UploadFile\""
                eval $SIGN_CMD > /tmp/.signedRequest
                echo "Log upload - configparamgen success"
                CB_SIGNED=`cat /tmp/.signedRequest`
                rm -f /tmp/.signedRequest
                S3_URL=`echo $CB_SIGNED | sed -e "s|?.*||g"`
                echo "serverUrl : $S3_URL"
                authorizationHeader=`echo $CB_SIGNED | sed -e "s|&|\", |g" -e "s|=|=\"|g" -e "s|.*filename|filename|g"`
                authorizationHeader="Authorization: OAuth realm=\"\", $authorizationHeader\""

                ######################CURL COMMAND PARAMETERS##############################
                #/fss/gw/curl       --> Path to curl.
                #-w                 --> Write to console.
                #%{http_code}       --> Header response code.
                #-d                 --> HTTP POST data.
                #$UploadFile        --> File to upload.
                #-o                 --> Write output to.
                #$OutputFile        --> Output File.
                #--cacert           --> certificate to verify peer.
                #/nvram/cacert.pem  --> Certificate.
                #$S3_URL            --> Public key URL Link.
                #--connect-timeout  --> Maximum time allowed for connection in seconds.
                #-m                 --> Maximum time allowed for the transfer in seconds.
                #-T                 --> Transfer FILE given to destination.
                #--interface        --> Network interface to be used [eg:erouter1]
                ##########################################################################
                if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
                    CURL_CMD="curl --tlsv1.2 --cacert $CA_CERT --connect-timeout 30 --interface $WAN_INTERFACE -H '$authorizationHeader' -w '%{http_code}\n' -o \"$OutputFile\" -d \"filename=$UploadFile\" '$S3_URL'"
                else
                    CURL_CMD="$CURLPATH/curl --tlsv1.2 --cacert $CA_CERT --connect-timeout 10 -H '$authorizationHeader' -w '%{http_code}\n' -o \"$OutputFile\" -d \"filename=$UploadFile\" --interface $WAN_INTERFACE '$S3_URL'"
                fi

                echo_t "File to be uploaded: $UploadFile"
                UPTIME=`uptime`
                echo_t "System Uptime is $UPTIME"
                echo_t "S3 URL is : $S3_URL"

                # Performing 3 tries for successful curl command execution.
                # $http_code --> Response code retrieved from HTTP_CODE file path.

                echo_t "Trial $retries..."
                # nice value can be normal as the first trial failed
                if [ $retries -ne 0 ]
                then
                    echo "Curl Command built: $CURL_CMD"
                    ret= eval $CURL_CMD > $HTTP_CODE

                    if [ -f $HTTP_CODE ];
                    then
                        http_code=$(awk '{print $0}' $HTTP_CODE)
                        echo_t "Codebig Communication - ret:$ret, http_code:$http_code"

                        if [ "$http_code" != "" ];then
                            echo_t "HttpCode received is : $http_code"
                            if [ $http_code -eq 200 ];then
                                rm -f $HTTP_CODE
                                break
                            fi
                            if [ $http_code -eq 401 ];then
                                rm -f $HTTP_CODE
                                # Even in case of 401 responce also we need to retry for max 3 times, we should not loop until we get a success response.
                                # continue
                            fi
                        fi
                    fi
                fi

                retries=`expr $retries + 1`
                sleep 30
            done
            rm -f /nvram/adjdate.txt
        fi


        # If 200, executing second curl command with the public key.
        if [ $http_code -eq 200 ];then
            #This means we have received the key to which we need to curl again in order to upload the file.
            #So get the key from FILENAME
            Key=$(awk -F\" '{print $0}' $OutputFile)
            #RDKB-14283 Remove Signature from CURL command in consolelog.txt and ArmConsolelog.txt
            RemSignature=`echo $Key | sed "s/Signature=.*&//"`

            echo_t "Generated KeyIs : "
            echo $RemSignature

            if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
                CURL_CMD="nice -n 20 curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"$Key\" --connect-timeout 30 -m 30"
            else
                CURL_CMD="nice -n 20 /fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"$Key\" --connect-timeout 30 -m 30"
            fi

            retries=0
            while [ "$retries" -lt 3 ]
            do
                echo_t "Trial $retries..."
                # nice value can be normal as the first trial failed
                if [ $retries -ne 0 ]; then
                    if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
                        CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"$Key\" --connect-timeout 30 -m 30"
                    else
                        CURL_CMD="/fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"$Key\" --connect-timeout 30 -m 30"
                    fi
                fi

                #RDKB-14283 Remove Signature from CURL command in consolelog.txt and ArmConsolelog.txt
                LogCurlCmd=`echo $CURL_CMD | sed "s/Signature=.*&//"`
                echo_t "Curl Command built: $LogCurlCmd"
                ret= eval $CURL_CMD > $HTTP_CODE
                if [ -f $HTTP_CODE ]; then
                    http_code=$(awk '{print $0}' $HTTP_CODE)

                    if [ "$http_code" != "" ];then
                        echo_t "HttpCode received is : $http_code"
                        if [ $http_code -eq 200 ];then
                            rm -f $HTTP_CODE
                            break
                        fi
                        if [ $http_code -eq 401 ];then
                            rm -f $HTTP_CODE
                            # Even in case of 401 responce also we need to retry for max 3 times, we should not loop until we get a success response.
                            # continue
                        fi
                    fi
                fi

                retries=`expr $retries + 1`
                sleep 30
            done

            # Response after executing curl with the public key is 200, then file uploaded successfully.
            if [ $http_code -eq 200 ];then
                echo_t "LOGS UPLOADED SUCCESSFULLY, RETURN CODE: $http_code"
                rm -rf $UploadFile
            fi

        #When 302, there is URL redirection.So get the new url from FILENAME and curl to it to get the key.
        elif [ $http_code -eq 302 ];then
            NewUrl=`grep -oP "(?<=HREF=\")[^\"]+(?=\")" $OutputFile`

            if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
                CURL_CMD="nice -n 20 curl --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" \"$NewUrl\" --interface $WAN_INTERFACE --connect-timeout 30 -m 30"
            else
                CURL_CMD="nice -n 20 /fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" \"$NewUrl\" --interface $WAN_INTERFACE --connect-timeout 30 -m 30"
            fi

            retries=0
            while [ "$retries" -lt 3 ]
            do
                echo_t "Trial $retries..."
                # nice value can be normal as the first trial failed
                if [ $retries -ne 0 ]; then
                    if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
                        CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" --cacert $CA_CERT --interface $WAN_INTERFACE \"$S3_URL\" --connect-timeout 30 -m 30"
                    else
                        CURL_CMD="/fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" --cacert $CA_CERT --interface $WAN_INTERFACE \"$S3_URL\" --connect-timeout 30 -m 30"
                    fi
                fi
                echo_t "Curl Command built: $CURL_CMD"
                ret= eval $CURL_CMD > $HTTP_CODE
                if [ -f $HTTP_CODE ]; then
                    http_code=$(awk '{print $0}' $HTTP_CODE)

                    if [ "$http_code" != "" ];then
                        echo_t "HttpCode received is : $http_code"
                        if [ $http_code -eq 200 ];then
                            rm -f $HTTP_CODE
                            break
                        fi
                    fi
                fi
                retries=`expr $retries + 1`
                sleep 30
            done



            #Executing curl with the response key when return code after the first curl execution is 200.
            if [ $http_code -eq 200 ];then
                Key=$(awk '{print $0}' $OutputFile)
                if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
                    CURL_CMD="nice -n 20 curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE  \"$Key\" --connect-timeout 10 -m 10"
                else
                    CURL_CMD="nice -n 20 /fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE  \"$Key\" --connect-timeout 10 -m 10"
                fi

                retries=0
                while [ "$retries" -lt 3 ]
                do
                    echo_t "Trial $retries..."
                    # nice value can be normal as the first trial failed
                    if [ $retries -ne 0 ]; then
                        if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
                            CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE  \"$Key\" --connect-timeout 10 -m 10"
                        else
                            CURL_CMD="/fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE  \"$Key\" --connect-timeout 10 -m 10"
                        fi
                    fi
                    echo_t "Curl Command built: $CURL_CMD"
                    ret= eval $CURL_CMD > $HTTP_CODE
                    if [ -f $HTTP_CODE ]; then
                        http_code=$(awk '{print $0}' $HTTP_CODE)

                        if [ "$http_code" != "" ];then

                            if [ $http_code -eq 200 ];then
                                rm -f $HTTP_CODE
                                break
                            fi
                        fi
                    fi
                    retries=`expr $retries + 1`
                    sleep 30
                done
                #Logs upload successful when the return code is 200 after the second curl execution.
                if [ $http_code -eq 200 ];then
                    echo_t "LOGS UPLOADED SUCCESSFULLY, RETURN CODE: $http_code"
                    result=0
                    rm -rf $UploadFile
                fi
            fi

        # Any other response code, log upload is unsuccessful.
        else
            echo_t "INVALID RETURN CODE: $http_code"
            echo_t "LOG UPLOAD UNSUCCESSFUL TO S3"
            echo_t "Do TFTP log Upload"
            TFTPLogUpload
            rm -rf $UploadFile
        fi

        echo_t $result
    done

    if [ "$UploadPath" != "" ] && [ -d $UploadPath ]; then
        rm -rf $UploadPath
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
   EROUTER_IP=`ifconfig $WAN_INTERFACE | grep "inet addr" | cut -d":" -f2 | cut -d" " -f1`
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
	   touch $WAITINGFORUPLOAD
	   retryUpload &
   fi
elif [ "$UploadProtocol" = "TFTP" ]
then
   echo_t "Upload TFTP_LOGS"
   TFTPLogUpload
fi

# Remove the log in progress flag
rm $REGULAR_UPLOAD
# removing event which is set in backupLogs.sh when wan goes down
sysevent set wan_event_log_upload no
