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

# Usage : ./opsLogUpload.sh <argument>
# Arguments:
#	upload - This will trigger an upload of current logs	
#	status - This will return the current status of upload
#	stop - This will stop the current upload
#
#
#

#source /etc/utopia/service.d/log_env_var.sh
#source /etc/utopia/service.d/log_capture_path.sh

RDK_LOGGER_PATH="/rdklogger"

source $RDK_LOGGER_PATH/logfiles.sh
source $RDK_LOGGER_PATH/utils.sh

if [ -f /nvram/logupload.properties -a $BUILD_TYPE != "prod" ];then
    . /nvram/logupload.properties
fi

SIGN_FILE="/tmp/.signedRequest_$$_`date +'%s'`"
DIRECT_BLOCK_TIME=86400
DIRECT_BLOCK_FILENAME="/tmp/.lastdirectfail_olu"

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

PING_PATH="/usr/sbin"
CURLPATH="/fss/gw"
MAC=`getMacAddressOnly`
timeRequested=`date "+%m-%d-%y-%I-%M%p"`
timeToUpload=`date`
LOG_FILE=$MAC"_Logs_$dt.tgz"
PATTERN_FILE="/tmp/pattern_file"
WAN_INTERFACE="erouter0"
SECONDV=`dmcli eRT getv Device.X_CISCO_COM_CableModem.TimeOffset | grep value | cut -d ":" -f 3 | tr -d ' ' `
UPLOAD_LOG_STATUS="/tmp/upload_log_status"


ARGS=$1
getBuildType()
{
   if [ "$UseCodeBig" = "1" ]; then
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
        CURL_CMD="$CURL_BIN --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" $URLENCODE_STRING -o \"$OutputFile\" --cacert /nvram/cacert.pem \"$S3_URL\" --interface $WAN_INTERFACE $addr_type --connect-timeout 30 -m 30"

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
         CURL_CMD="$CURL_BIN --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" $URLENCODE_STRING -o \"$OutputFile\" --cacert /nvram/cacert.pem \"$S3_URL_SIGN\" --interface $WAN_INTERFACE $addr_type -H '$authorizationHeader' --connect-timeout 30 -m 30"
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

HTTPLogUploadOnRequest()
{
    cd $blog_dir

    # If interface doesnt have ipv6 address then we will force the curl to go with ipv4.
    # Otherwise we will not specify the ip address family in curl options
    addr_type=""
    [ "x`ifconfig $WAN_INTERFACE | grep inet6 | grep -i 'Global'`" != "x" ] || addr_type="-4"

    UploadFile=`ls | grep "tgz"`

    S3_MD5SUM=""
    echo "RFC_EncryptCloudUpload_Enable:$encryptionEnable"
    if [ "$encryptionEnable" == "true" ]; then
        S3_MD5SUM="$(openssl md5 -binary < $UploadFile | openssl enc -base64)"
        URLENCODE_STRING="--data-urlencode \"md5=$S3_MD5SUM\""
    fi

    $first_conn || $sec_conn || { echo "LOG UPLOAD UNSUCCESSFUL,INVALID RETURN CODE: $http_code" ; rm -rf $blog_dir$timeRequested  ; }

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
           CURL_CMD_FOR_ECHO="curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"<hidden key>\" --connect-timeout 30 -m 30"
        else
           CURL_CMD="/fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE $Key --connect-timeout 30 -m 30"
           CURL_CMD_FOR_ECHO="/fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"<hidden key>\" --connect-timeout 30 -m 30"
        fi
	echo_t "Curl Command built: $CURL_CMD_FOR_ECHO"

        retries=0
        while [ "$retries" -lt "3" ]
        do 
	    echo_t "Trial $retries..."                  
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
	    #Remove all log directories
	     rm -rf $blog_dir
        fi

    #When 302, there is URL redirection.So get the new url from FILENAME and curl to it to get the key. 
    elif [ "$http_code" = "302" ];then
		echo_t "Inside 302"
        NewUrl=`grep -oP "(?<=HREF=\")[^\"]+(?=\")" $OutputFile`
        if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
           CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" \"$NewUrl\" --interface $WAN_INTERFACE --connect-timeout 30 -m 30"
        else
           CURL_CMD="/fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" \"$NewUrl\" --interface $WAN_INTERFACE --connect-timeout 30 -m 30"
        fi
        echo_t "Curl Command built: `echo "$CURL_CMD" | sed -ne 's#AWSAccessKeyId=.*Signature=.*&#<hidden key>#p'`"

        retries=0
        while [ "$retries" -lt "3" ]
        do       
	    echo_t "Trial $retries..."            
            ret= eval $CURL_CMD > $HTTP_CODE
            if [ -f $HTTP_CODE ];
	    then
		http_code=$(echo "$HTTP_CODE" | awk '{print $0}' )

		if [ "$http_code" != "" ];then
				echo_t "HttpCode received is : $http_code"
	       		if [ "$http_code" = "200" ];then
					echo $http_code > $UPLOADRESULT
	       			break
			else
				echo "failed" > $UPLOADRESULT
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
        if [ "$encryptionEnable" != "true" ]; then
            Key=\"$Key\"
        fi
        CURL_CMD="$CURL_BIN --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE $addr_type  $Key --connect-timeout 30 -m 30"
        CURL_REMOVE_HEADER=`echo $CURL_CMD | sed "s/AWSAccessKeyId=.*Signature=.*&//g;s/\"//g;s/.*https/https/g"`
        retries=0
        while [ "$retries" -lt "3" ]
        do       
	    echo_t "Trial $retries..."              
            echo_t "Curl Command built: $CURL_REMOVE_HEADER"
            HTTP_CODE=`ret= eval $CURL_CMD`
            if [ "x$HTTP_CODE" != "x" ];
	    then
		http_code=$(echo "$HTTP_CODE" | awk '{print $0}' )

		if [ "$http_code" != "" ];then
	
	       		if [ "$http_code" = "200" ];then
					echo $http_code > $UPLOADRESULT
	       			break
			else
				echo "failed" > $UPLOADRESULT
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
	    #Remove all log directories
	    rm -rf $blog_dir
            result=0
        fi
    fi
    # Any other response code, log upload is unsuccessful.
    else 
       	echo_t "LOG UPLOAD UNSUCCESSFUL,INVALID RETURN CODE: $http_code"
	#Keep tar ball and remove only the log folder
	rm -rf $blog_dir$timeRequested
		
    fi    
    echo_t $result
}

uploadOnRequest()
{
	if [ ! -e $UPLOAD_LOG_STATUS ]; then
		touch $UPLOAD_LOG_STATUS
	fi
	echo "Triggered `date`" > $UPLOAD_LOG_STATUS
	curDir=`pwd`
        if [  -d $blog_dir ] ; then
            rm -rf $blog_dir/*
        fi
        mkdir -p $blog_dir$timeRequested
        cp /version.txt $blog_dir$timeRequested
        dest=$blog_dir$timeRequested/
         
	cd $LOG_PATH
	FILES=`ls`

	# Put system descriptor in log file
	createSysDescr

	for fname in $FILES
	do
           # Copy all log files from the log directory to non-volatile memory
           cp $fname $dest
	done

	cd $blog_dir
	# Tar log files
	# Syncing ATOM side logs
	if [ "$ATOM_SYNC" = "yes" ]
	then
		echo_t "Check whether ATOM ip accessible before syncing ATOM side logs"
		if [ -f $PING_PATH/ping_peer ]
		then
   		        PING_RES=`ping_peer`
			CHECK_PING_RES=`echo $PING_RES | grep "packet loss" | cut -d"," -f3 | cut -d"%" -f1`

			if [ "$CHECK_PING_RES" != "" ]
			then
				if [ "$CHECK_PING_RES" != "100" ]
				then
					echo_t "Ping to ATOM ip success, syncing ATOM side logs"
					protected_rsync $blog_dir$timeRequested
#nice -n 20 rsync root@$ATOM_IP:$ATOM_LOG_PATH$ATOM_FILE_LIST $LOG_UPLOAD_ON_REQUEST$timeRequested/ > /dev/null 2>&1
				else
					echo_t "Ping to ATOM ip falied, not syncing ATOM side logs"
				fi
			else
				echo_t "Ping to ATOM ip falied, not syncing ATOM side logs"
			fi
		fi

	fi
	if [ "$codebig_enabled" == "yes" ]; then
		echo "*.tgz" > $PATTERN_FILE # .tgz should be excluded while tar
		tar -X $PATTERN_FILE -cvzf $MAC"_Logs_$timeRequested.tgz" /tmp/loguploadonrequest/$timeRequested
		rm $PATTERN_FILE
		rm -rf /tmp/loguploadonrequest/$timeRequested
	else
		echo "*.tgz" > $PATTERN_FILE # .tgz should be excluded while tar
		tar -X $PATTERN_FILE -cvzf $MAC"_Logs_$timeRequested.tgz" $timeRequested
		rm $PATTERN_FILE
	fi
	echo_t "Created backup of all logs..."
 	ls

	#if [ ! -e $UPLOAD_ON_REQUEST ] && [ ! -e $REGULAR_UPLOAD ]
	#then

	touch $UPLOAD_ON_REQUEST
	#TFTPLogUploadOnRequest
	echo_t "Calling function to uploadLogs"
	echo "In Progress `date`" > $UPLOAD_LOG_STATUS
	HTTPLogUploadOnRequest
	#fi
	cd $curDir
	echo_t "Log file Upload completed..."

	# Remove the in progress flag 
	rm -rf $UPLOAD_ON_REQUEST
	#rm -rf $LOG_UPLOAD_ON_REQUEST

	# When curl fails we can rely on "failed string"
	FAILED=`cat $UPLOADRESULT | grep "failed"`

	# curl always throw error code with curl string in it
	isCurlPresent=`cat $UPLOADRESULT | grep "curl"`

	# If curl never tries to upload result file will be blank
	DIDTRY=`cat $UPLOADRESULT`

	if [ "$FAILED" != "" ] || [ "$DIDTRY" = "" ] || [ "$isCurlPresent" != "" ]
	then
		# We have hit error condition. Exit with error code
		echo "Failed `date`" > $UPLOAD_LOG_STATUS
	else
		# Last Log upload success
		echo "Complete `date`" > $UPLOAD_LOG_STATUS
	fi
}

get_Codebigconfig
if [ "$UseCodeBig" = "1" ]; then
      blog_dir="/tmp/loguploadonrequest/"
else
      blog_dir=$LOG_UPLOAD_ON_REQUEST
fi

if [ "$ARGS" = "upload" ]
then
	# Call function to upload log files on reboot
	uploadOnRequest
elif [ "$ARGS" = "stop" ]
then
	PID_Upload=`ps | grep uploadOnRequest | head -1 | cut -f2 -d" "`
	kill -9 $PID_Upload
	
	# We don't want to kill any regular log upload in progress
	if [ -e $UPLOAD_ON_REQUEST ] && [ ! -e $REGULAR_UPLOAD ]
	then
		PID_CURL=`ps | grep curl | grep tftp | head -1 | cut -f2 -d" "`
		kill -9 $PID_CURL
		rm -rf $UPLOAD_ON_REQUEST
	fi
	
	if [ -d $blog_dir ]
	then
		rm -rf $blog_dir
	fi
	rm $UPLOAD_LOG_STATUS
	
fi

#sleep 3


