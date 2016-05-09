#!/bin/sh

#
# If not stated otherwise in this file or this component's Licenses.txt
# file the following copyright and licenses apply:
#
# Copyright 2015 RDK Management
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
#

# Usage : ./opsLogUpload.sh <argument>
# Arguments:
#	upload - This will trigger an upload of current logs	
#	status - This will return the current status of upload
#	stop - This will stop the current upload
#
#
#

source /fss/gw/etc/utopia/service.d/log_env_var.sh
source /etc/utopia/service.d/log_capture_path.sh
source $RDK_LOGGER_PATH/logfiles.sh
source $RDK_LOGGER_PATH/utils.sh

# This check is put to determine whether the image is Yocto or not
if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
   export PATH=$PATH:/fss/gw/
fi

CURLPATH="/fss/gw"
MAC=`getMacAddressOnly`
timeRequested=`date "+%m-%d-%y-%I-%M%p"`
timeToUpload=`date`
LOG_FILE=$MAC"_Logs_$dt.tgz"

WAN_INTERFACE="erouter0"


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
   IMAGENAME=`cat /fss/gw/version.txt | grep ^imagename= | cut -d "=" -f 2`
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
	echo "Log file $FILE_NAME is getting uploaded to $TFTP_SERVER for build type "$BUILD_TYPE"..."
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
    if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
        CURL_CMD="curl -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" --cacert /nvram/cacert.pem \"$S3_URL\" --interface $WAN_INTERFACE --connect-timeout 10 -m 10"
    else
        CURL_CMD="/fss/gw/curl -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" --cacert /nvram/cacert.pem \"$S3_URL\" --interface $WAN_INTERFACE --connect-timeout 10 -m 10"
    fi

    echo "Curl Command built: $CURL_CMD"
    echo "File to be uploaded: $UploadFile"
    echo "S3 URL is : $S3_URL"

    # Performing 3 tries for successful curl command execution.
    # $http_code --> Response code retrieved from HTTP_CODE file path.
    retries=0
    while [ "$retries" -lt 3 ]
    do      
	echo "Trial $retries..."              
        ret= eval $CURL_CMD > $HTTP_CODE

	if [ -f $HTTP_CODE ];
	then
		http_code=$(awk '{print $0}' $HTTP_CODE)

		if [ "$http_code" != "" ];then
			echo "HttpCode received is : $http_code"
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
        sleep 1
    done

    # If 200, executing second curl command with the public key.
    if [ $http_code -eq 200 ];then
        #This means we have received the key to which we need to curl again in order to upload the file.
        #So get the key from FILENAME
        Key=$(awk '{print $0}' $OutputFile)
	
		echo "Generated KeyIs : "
		echo $Key
        if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
           CURL_CMD="curl -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"$Key\" --connect-timeout 10 -m 10"
        else
           CURL_CMD="/fss/gw/curl -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"$Key\" --connect-timeout 10 -m 10"
        fi
               
		echo "Curl Command built: $CURL_CMD"
        retries=0
        while [ "$retries" -lt 3 ]
        do 
	    echo "Trial $retries..."                  
            ret= eval $CURL_CMD > $HTTP_CODE
            if [ -f $HTTP_CODE ];
	    then
		http_code=$(awk '{print $0}' $HTTP_CODE)

		if [ "$http_code" != "" ];then
			echo "HttpCode received is : $http_code"
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
            sleep 1
        done

	# Response after executing curl with the public key is 200, then file uploaded successfully.
        if [ $http_code -eq 200 ];then
	     echo "LOGS UPLOADED SUCCESSFULLY, RETURN CODE: $http_code"
        fi

    #When 302, there is URL redirection.So get the new url from FILENAME and curl to it to get the key. 
    elif [ $http_code -eq 302 ];then
		echo "Inside 302"
        NewUrl=`grep -oP "(?<=HREF=\")[^\"]+(?=\")" $OutputFile`
        if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
           CURL_CMD="curl -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" \"$NewUrl\" --interface $WAN_INTERFACE --connect-timeout 10 -m 10"
        else
           CURL_CMD="/fss/gw/curl -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" \"$NewUrl\" --interface $WAN_INTERFACE --connect-timeout 10 -m 10"
        fi
		echo "Curl Command built: $CURL_CMD"               

        retries=0
        while [ "$retries" -lt 3 ]
        do       
	    echo "Trial $retries..."            
            ret= eval $CURL_CMD > $HTTP_CODE
            if [ -f $HTTP_CODE ];
	    then
		http_code=$(awk '{print $0}' $HTTP_CODE)

		if [ "$http_code" != "" ];then
				echo "HttpCode received is : $http_code"
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
            sleep 1
        done

       
        #Executing curl with the response key when return code after the first curl execution is 200.
        if [ $http_code -eq 200 ];then
        Key=$(awk '{print $0}' $OutputFile)
        if [ -f /etc/os-release ] || [ -f /etc/device.properties ]; then
           CURL_CMD="curl -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE  \"$Key\" --connect-timeout 10 -m 10"
        else
           CURL_CMD="/fss/gw/curl -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE  \"$Key\" --connect-timeout 10 -m 10"
        fi       
		echo "Curl Command built: $CURL_CMD"               
        retries=0
        while [ "$retries" -lt 3 ]
        do       
	    echo "Trial $retries..."              
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
            sleep 1
        done
        #Logs upload successful when the return code is 200 after the second curl execution.
        if [ $http_code -eq 200 ];then
            echo "LOGS UPLOADED SUCCESSFULLY, RETURN CODE: $http_code"
            result=0
        fi
    fi
    # Any other response code, log upload is unsuccessful.
    else 
       	echo "LOG UPLOAD UNSUCCESSFUL,INVALID RETURN CODE: $http_code"
	echo "Do TFTP log Upload"
	TFTPLogUploadOnRequest
		
    fi    
    echo $result

}

uploadOnRequest()
{
	curDir=`pwd`
	if [ ! -d "$LOG_UPLOAD_ON_REQUEST" ]
	then
	    mkdir $LOG_UPLOAD_ON_REQUEST
	fi

	mkdir -p $LOG_UPLOAD_ON_REQUEST$timeRequested

	cd $LOG_PATH
	FILES=`ls`

	for fname in $FILES
	do
		# Copy all log files from the log directory to non-volatile memory

		cp $fname $LOG_UPLOAD_ON_REQUEST$timeRequested ; >$fname;

	done

	cd $LOG_UPLOAD_ON_REQUEST
	# Tar log files 	
	tar -cvzf $MAC"_Logs_$timeRequested.tgz" $timeRequested
	echo "Created backup of all logs..."
 	ls

	#if [ ! -e $UPLOAD_ON_REQUEST ] && [ ! -e $REGULAR_UPLOAD ]
	#then
	if [ -e $UPLOAD_ON_REQUEST_SUCCESS ]
	then
		rm -rf $UPLOAD_ON_REQUEST_SUCCESS
	fi
	touch $UPLOAD_ON_REQUEST
	#TFTPLogUploadOnRequest
	echo "Calling function to uploadLogs"
	HTTPLogUploadOnRequest
	#fi
	cd $curDir
	echo "Log file Upload completed..."
	# Indicate upload on request is success
	touch $UPLOAD_ON_REQUEST_SUCCESS
	echo $timeToUpload > $UPLOAD_ON_REQUEST_SUCCESS

	# Remove the in progress flag and all log directories
	rm -rf $UPLOAD_ON_REQUEST
	rm -rf $LOG_UPLOAD_ON_REQUEST
   
}


if [ "$ARGS" = "status" ]
then
	if [ ! -d $LOG_UPLOAD_ON_REQUEST ] 
	then
		if [ -e $UPLOAD_ON_REQUEST_SUCCESS ] 
		then
			if [ -e $UPLOADRESULT ]
			then
				# When curl fails we can rely on "failed string"
				FAILED=`cat $UPLOADRESULT | grep "failed"`

				# curl always throw error code with curl string in it
				isCurlPresent=`cat $UPLOADRESULT | grep "curl"`
				
				# If curl never tries to upload result file will be blank
				DIDTRY=`cat $UPLOADRESULT`

				if [ "$FAILED" != "" ] || [ "$DIDTRY" = "" ] || [ "$isCurlPresent" != "" ]
				then
					# We have hit error condition. Exit with error code
					exit 3
				else
					# Last Log upload success
					exit 4
				fi
			fi
			
		else
			# Log upload not triggered
			exit 0
		fi
	elif [ -d $LOG_UPLOAD_ON_REQUEST ] 
	then
		if [ ! -e $UPLOAD_ON_REQUEST ]
		then
			# Log upload is triggered
			exit 1
		fi
		if [ -e $UPLOAD_ON_REQUEST ]
		then
			# Log upload in progress
			exit 2
		fi
	fi
elif [ "$ARGS" = "upload" ]
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
	
fi

#sleep 3


