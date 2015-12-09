#!/bin/sh
# Script responsible for log upload based on protocol

RDK_LOGGER_PATH="/fss/gw/rdklogger"
LOG_BACK_UP_REBOOT="/nvram/logbackupreboot/"
LOGTEMPPATH="/var/tmp/backuplogs/"

. $RDK_LOGGER_PATH/utils.sh 
. $RDK_LOGGER_PATH/logfiles.sh



if [ $# -ne 4 ]; then 
     #echo "USAGE: $0 <TFTP Server IP> <UploadProtocol> <UploadHttpLink> <uploadOnReboot>"
     echo "USAGE: $0 $1 $2 $3 $4"
fi


# assign the input arguments
TFTP_SERVER=$1
UploadProtocol=$2
UploadHttpLink=$3
UploadOnReboot=$4

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
LOG_PATH="/var/tmp/logs/"
LOG_BACK_UP_PATH="/nvram/logbackup/"

http_code=0
OutputFile='/tmp/httpresult.txt'
HTTP_CODE="/tmp/curl_httpcode"

# Function which will upload logs to TFTP server
TFTPLogUpload()
{
	if [ "$UploadOnReboot" = "true" ]
	then
		cd $LOG_BACK_UP_REBOOT
	else
		cd $LOG_BACK_UP_PATH
	fi

	FILE_NAME=`ls | grep "tgz"`
	echo "Log file $FILE_NAME is getting uploaded to $TFTP_SERVER..."
	#tftp -l $FILE_NAME -p $TFTP_SERVER  
	$CURLPATH/curl -T $FILE_NAME  --interface $WAN_INTERFACE tftp://$TFTP_SERVER

	sleep 3
   
}

# Function which will upload logs to HTTP S3 server
HttpLogUpload()
{   
    # Upload logs to "LOG_BACK_UP_REBOOT" upon reboot else to the default path "LOG_BACK_UP_PATH"	
    if [ "$UploadOnReboot" = "true" ]
    then
		cd $LOG_BACK_UP_REBOOT

    else
		cd $LOG_BACK_UP_PATH

    fi

    UploadFile=`ls | grep "tgz"`
    S3_URL=$UploadHttpLink
    
	

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
    CURL_CMD="/fss/gw/curl -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" --cacert $CA_CERT --interface $WAN_INTERFACE \"$S3_URL\" --connect-timeout 10 -m 10"
    
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
				rm -f $HTTP_CODE
	       			break
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

        CURL_CMD="/fss/gw/curl -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"$Key\" --connect-timeout 10 -m 10"
    	
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
				rm -f $HTTP_CODE
	       			break
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
        NewUrl=`grep -oP "(?<=HREF=\")[^\"]+(?=\")" $OutputFile`
        CURL_CMD="/fss/gw/curl -w '%{http_code}\n' -d \"filename=$UploadFile\" -o \"$OutputFile\" \"$NewUrl\" --interface $WAN_INTERFACE --connect-timeout 10 -m 10"
	
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
				rm -f $HTTP_CODE
	       			break
	       		fi
		fi
	    fi
            retries=`expr $retries + 1`
            sleep 1
        done

   
        #Executing curl with the response key when return code after the first curl execution is 200.
        if [ $http_code -eq 200 ];then
        Key=$(awk '{print $0}' $OutputFile)
        CURL_CMD="/fss/gw/curl -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE  \"$Key\" --connect-timeout 10 -m 10"
             
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
				rm -f $HTTP_CODE
	       			break
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
	    	echo "INVALID RETURN CODE: $http_code"
        	echo "LOG UPLOAD UNSUCCESSFUL TO S3"
		echo "Do TFTP log Upload"
		TFTPLogUpload
		
    fi    
    echo $result
}


# Flag that a log upload is in progress. 
if [ -e /var/tmp/uploading ]
then
	rm /var/tmp/uploading
fi

touch /var/tmp/uploading

#Check the protocol through which logs need to be uploaded
if [ "$UploadProtocol" = "HTTP" ]
then
   echo "Upload HTTP_LOGS"
   HttpLogUpload
elif [ "$UploadProtocol" = "TFTP" ]
then
   echo "Upload TFTP_LOGS"
   TFTPLogUpload
fi

# Remove the directory from non volatile memory
curDir=`pwd`
cd $LOG_BACK_UP_PATH
dirName=`ls -d */`
rm -rf $dirName
cd $curDir

# Remove the log in progress flag
rm /var/tmp/uploading
