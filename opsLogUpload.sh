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

source /etc/utopia/service.d/log_env_var.sh
source /etc/utopia/service.d/log_capture_path.sh
source $RDK_LOGGER_PATH/logfiles.sh
source $RDK_LOGGER_PATH/utils.sh

# This check is put to determine whether the image is Yocto or not
if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
   export PATH=$PATH:/fss/gw/
fi

if [ -f /etc/device.properties ]; then
	codebig_enabled=`cat /etc/device.properties | grep CODEBIG_ENABLED | cut -f2 -d=`
fi

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


TFTPLogUploadOnRequest()
{

	# Get build type and the server depending on build type.
	BUILD_TYPE=`getBuildType`
	TFTP_SERVER=`getTFTPServer $BUILD_TYPE`

	# We will default to logs.xcal.tv
	if [ $TFTP_SERVER = "" ]
	then
		TFTP_SERVER="logs.xcal.tv"
	fi

	cd $LOG_UPLOAD_ON_REQUEST
	
	# Get the file and upload it
	FILE_NAME=`ls | grep "tgz"`
	echo_t "Log file $FILE_NAME is getting uploaded to $TFTP_SERVER for build type "$BUILD_TYPE"..."
    # this is still insecure!
    if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
       curl -T $FILE_NAME --interface $WAN_INTERFACE tftp://$TFTP_SERVER --connect-timeout 10 -m 10 2> $UPLOADRESULT 
    else
	   $CURLPATH/curl -T $FILE_NAME --interface $WAN_INTERFACE tftp://$TFTP_SERVER --connect-timeout 10 -m 10 2> $UPLOADRESULT
    fi

	sleep 3
   
}

HTTPLogUploadOnRequest()
{
    cd $LOG_UPLOAD_ON_REQUEST

    UploadFile=`ls | grep "tgz"`
	if [ "$codebig_enabled" == "yes" ]; then
		retries=0
        while [ "$retries" -lt 10 ]
        do
        echo "Trial $retries..."

        if [ $retries -ne 0 ]
        then
                if [ -f /nvram/adjdate.txt ];
                then
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
        echo "$0 --> LOG UPLOAD UNSUCCESSFUL TO S3 because unable to write date info to /nvram/adjdate.txt"
        rm -rf $UploadFile
        exit
        fi
        SIGN_CMD="configparamgen 1 \"/cgi-bin/rdkb.cgi?filename=$UploadFile\""
        eval $SIGN_CMD > /var/.signedRequest
        echo "Log upload - configparamgen success"
        CB_SIGNED=`cat /var/.signedRequest`
        rm -f /var/.signedRequest
        rm -f /nvram/adjdate.txt
        S3_URL=`echo $CB_SIGNED | sed -e "s|?.*||g"`
        echo "serverUrl : $S3_URL"
        authorizationHeader=`echo $CB_SIGNED | sed -e "s|&|\", |g" -e "s|=|=\"|g" -e "s|.*filename|filename|g"`
        authorizationHeader="Authorization: OAuth realm=\"\", $authorizationHeader\""
	fi
    ######################CURL COMMAND PARAMETERS##############################
    #/fss/gw/curl 	--> Path to curl.
    #-w           	--> Write to console.
    #%{http_code} 	--> Header response code.
    #-d           	--> HTTP POST data.
    #$UploadFile  	--> File to upload.
    #-o           	--> Write output to.
    #$OutputFile  	--> Output File.
    #--cacert     	--> certificate to verify peer.
    #/nvram/cacert.pem	--> Certificate.
    #$S3_URL		--> Public key URL Link.
    #--connect-timeout	--> Maximum time allowed for connection in seconds. 
    #-m			--> Maximum time allowed for the transfer in seconds.
    #-T			--> Transfer FILE given to destination.
    #--interface	--> Network interface to be used [eg:erouter1]
    ##########################################################################
    if [ "$codebig_enabled" == "yes" ]; then
	if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
		CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" --cacert /nvram/cacert.pem \"$S3_URL\" --interface $WAN_INTERFACE -H '$authorizationHeader' --connect-timeout 30 -m 30"
	else
		CURL_CMD="/fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" --cacert /nvram/cacert.pem \"$S3_URL\" --interface $WAN_INTERFACE -H '$authorizationHeader' --connect-timeout 30 -m 30"
	fi
    else
	if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
		CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" --cacert /nvram/cacert.pem \"$S3_URL\" --interface $WAN_INTERFACE --connect-timeout 30 -m 30"
	else
		CURL_CMD="/fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" --cacert /nvram/cacert.pem \"$S3_URL\" --interface $WAN_INTERFACE --connect-timeout 30 -m 30"
	fi
    fi

    echo_t "Curl Command built: $CURL_CMD"
    echo_t "File to be uploaded: $UploadFile"
    echo_t "S3 URL is : $S3_URL"

    # Performing 3 tries for successful curl command execution.
    # $http_code --> Response code retrieved from HTTP_CODE file path.
    retries=0
    while [ "$retries" -lt 3 ]
    do      
	echo_t "Trial $retries..."              
        ret= eval $CURL_CMD > $HTTP_CODE

	if [ -f $HTTP_CODE ];
	then
		http_code=$(awk '{print $0}' $HTTP_CODE)

		if [ "$http_code" != "" ];then
			echo_t "HttpCode received is : $http_code"
	       		if [ $http_code -eq 200 ];then
					echo $http_code > $UPLOADRESULT
					rm -f $HTTP_CODE
	       			break
			else
				echo "failed" > $UPLOADRESULT
	       	fi
		fi
	fi

        retries=`expr $retries + 1`
        sleep 30
    done

    # If 200, executing second curl command with the public key.
    if [ $http_code -eq 200 ];then
        #This means we have received the key to which we need to curl again in order to upload the file.
        #So get the key from FILENAME
        Key=$(awk '{print $0}' $OutputFile)
	
		echo_t "Generated KeyIs : "
		echo $Key
        if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
           CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"$Key\" --connect-timeout 30 -m 30"
        else
           CURL_CMD="/fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"$Key\" --connect-timeout 30 -m 30"
        fi
               
		echo_t "Curl Command built: $CURL_CMD"
        retries=0
        while [ "$retries" -lt 3 ]
        do 
	    echo_t "Trial $retries..."                  
            ret= eval $CURL_CMD > $HTTP_CODE
            if [ -f $HTTP_CODE ];
	    then
		http_code=$(awk '{print $0}' $HTTP_CODE)

		if [ "$http_code" != "" ];then
			echo_t "HttpCode received is : $http_code"
	       		if [ $http_code -eq 200 ];then
					echo $http_code > $UPLOADRESULT
					rm -f $HTTP_CODE
	       			break
			else
				echo "failed" > $UPLOADRESULT
	       	fi
		fi
	fi
            retries=`expr $retries + 1`
            sleep 30
        done

	# Response after executing curl with the public key is 200, then file uploaded successfully.
        if [ $http_code -eq 200 ];then
	     echo_t "LOGS UPLOADED SUCCESSFULLY, RETURN CODE: $http_code"
	    #Remove all log directories
	     rm -rf $LOG_UPLOAD_ON_REQUEST
        fi

    #When 302, there is URL redirection.So get the new url from FILENAME and curl to it to get the key. 
    elif [ $http_code -eq 302 ];then
		echo_t "Inside 302"
        NewUrl=`grep -oP "(?<=HREF=\")[^\"]+(?=\")" $OutputFile`
        if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
           CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" \"$NewUrl\" --interface $WAN_INTERFACE --connect-timeout 30 -m 30"
        else
           CURL_CMD="/fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" \"$NewUrl\" --interface $WAN_INTERFACE --connect-timeout 30 -m 30"
        fi
		echo_t "Curl Command built: $CURL_CMD"               

        retries=0
        while [ "$retries" -lt 3 ]
        do       
	    echo_t "Trial $retries..."            
            ret= eval $CURL_CMD > $HTTP_CODE
            if [ -f $HTTP_CODE ];
	    then
		http_code=$(awk '{print $0}' $HTTP_CODE)

		if [ "$http_code" != "" ];then
				echo_t "HttpCode received is : $http_code"
	       		if [ $http_code -eq 200 ];then
					echo $http_code > $UPLOADRESULT
					rm -f $HTTP_CODE
	       			break
			else
				echo "failed" > $UPLOADRESULT
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
           CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE  \"$Key\" --connect-timeout 30 -m 30"
        else
           CURL_CMD="/fss/gw/curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE  \"$Key\" --connect-timeout 30 -m 30"
        fi       
		echo_t "Curl Command built: $CURL_CMD"               
        retries=0
        while [ "$retries" -lt 3 ]
        do       
	    echo_t "Trial $retries..."              
            ret= eval $CURL_CMD > $HTTP_CODE
            if [ -f $HTTP_CODE ];
	    then
		http_code=$(awk '{print $0}' $HTTP_CODE)

		if [ "$http_code" != "" ];then
	
	       		if [ $http_code -eq 200 ];then
					echo $http_code > $UPLOADRESULT
					rm -f $HTTP_CODE
	       			break
			else
				echo "failed" > $UPLOADRESULT
	       	fi
		fi
	fi
            retries=`expr $retries + 1`
            sleep 30
        done
        #Logs upload successful when the return code is 200 after the second curl execution.
        if [ $http_code -eq 200 ];then
            echo_t "LOGS UPLOADED SUCCESSFULLY, RETURN CODE: $http_code"
	    #Remove all log directories
	    rm -rf $LOG_UPLOAD_ON_REQUEST
            result=0
        fi
    fi
    # Any other response code, log upload is unsuccessful.
    else 
       	echo_t "LOG UPLOAD UNSUCCESSFUL,INVALID RETURN CODE: $http_code"
	echo_t "Do TFTP log Upload"
	TFTPLogUploadOnRequest
	#Keep tar ball and remove only the log folder
	rm -rf $LOG_UPLOAD_ON_REQUEST$timeRequested
		
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
	if [ ! -d "$LOG_UPLOAD_ON_REQUEST" ]
	then
	    mkdir $LOG_UPLOAD_ON_REQUEST
	else
            rm -rf $LOG_UPLOAD_ON_REQUEST/*
        fi
	if [ "$codebig_enabled" != "yes" ]; then
		mkdir -p $LOG_UPLOAD_ON_REQUEST$timeRequested
		cp /version.txt $LOG_UPLOAD_ON_REQUEST$timeRequested
	fi
        if [ ! -d "/tmp/loguploadonrequest" ] && [ "$codebig_enabled" == "yes" ]
        then
                mkdir "/tmp/loguploadonrequest"
        fi
	if [ "$codebig_enabled" == "yes" ]; then
		mkdir "/tmp/loguploadonrequest/$timeRequested"
		cp /version.txt /tmp/loguploadonrequest/$timeRequested
		dest=/tmp/loguploadonrequest/$timeRequested/
	fi
	cd $LOG_PATH
	FILES=`ls`

	# Put system descriptor in log file
	createSysDescr

	cp /version.txt $LOG_UPLOAD_ON_REQUEST$timeRequested

	for fname in $FILES
	do
		# Copy all log files from the log directory to non-volatile memory
		if [ "$codebig_enabled" == "yes" ]; then
			cp $fname $dest
		else
			cp $fname $LOG_UPLOAD_ON_REQUEST$timeRequested
		fi

	done

	cd $LOG_UPLOAD_ON_REQUEST
	# Tar log files
	# Syncing ATOM side logs
	if [ "$atom_sync" = "yes" ]
	then
		echo_t "Check whether ATOM ip accessible before syncing ATOM side logs"
		if [ -f $PING_PATH/ping_peer ]
		then
   		        PING_RES=`ping_peer`
			CHECK_PING_RES=`echo $PING_RES | grep "packet loss" | cut -d"," -f3 | cut -d"%" -f1`

			if [ "$CHECK_PING_RES" != "" ]
			then
				if [ "$CHECK_PING_RES" -ne 100 ] 
				then
					echo_t "Ping to ATOM ip success, syncing ATOM side logs"
					if [ "$codebig_enabled" == "yes" ]; then
						protected_rsync /tmp/loguploadonrequest/$timeRequested
					else
						protected_rsync $LOG_UPLOAD_ON_REQUEST$timeRequested/
					fi
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
		tar -X $PATTERN_FILE -cvzf $MAC"_Lgs_$timeRequested.tgz" /tmp/loguploadonrequest/$timeRequested
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
	
	if [ -d $LOG_UPLOAD_ON_REQUEST ]
	then
		rm -rf $LOG_UPLOAD_ON_REQUEST
	fi
	rm $UPLOAD_LOG_STATUS
	
fi

#sleep 3


