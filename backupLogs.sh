#!/bin/sh

source /fss/gw/etc/utopia/service.d/log_env_var.sh
source /etc/utopia/service.d/log_capture_path.sh

source $RDK_LOGGER_PATH/logfiles.sh
source $RDK_LOGGER_PATH/utils.sh

MAC=`getMacAddressOnly`
dte=`date "+%m-%d-%y-%I-%M%p"`
LOG_FILE=$MAC"_Logs_$dt.tgz"
needReboot="true"

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


BUILD_TYPE=`getBuildType`
SERVER=`getTFTPServer $BUILD_TYPE`

backupLogsonReboot()
{
	curDir=`pwd`
	if [ ! -d "$LOG_BACK_UP_REBOOT" ]
	then
	    mkdir $LOG_BACK_UP_REBOOT
	fi

	rm -rf $LOG_BACK_UP_REBOOT*
	
	cd $LOG_BACK_UP_REBOOT
	mkdir $dte

	# Put system descriptor string in log file
	createSysDescr

	cd $LOG_PATH
	FILES=`ls`

	for fname in $FILES
	do
		# Copy all log files from the log directory to non-volatile memory
		cp $fname $LOG_BACK_UP_REBOOT$dte ; >$fname;

	done



    # No need of checking whether file exists. Move everything

    #ret=`allFileExists $LOG_PATH`
	
	#if [ "$ret" = "yes" ]
	#then
	    #moveFiles $LOG_PATH $LOG_BACK_UP_REBOOT$dte
	#    moveFiles $LOGTEMPPATH $LOG_BACK_UP_REBOOT$dte
	#elif [ "$ret" = "no" ]
	#then

	#	for fname in $LOG_FILES_NAMES
	#	do
	#	    	if [ -f "$LOGTEMPPATH$fname" ] ; then moveFile $LOGTEMPPATH$fname $LOG_BACK_UP_REBOOT$dte; fi
	#	done

	#fi
	cd $LOG_BACK_UP_REBOOT
	cp /fss/gw/version.txt $LOG_BACK_UP_REBOOT$dte
	tar -cvzf $MAC"_Logs_$dte.tgz" $dte
	echo "Created backup of all logs..."
	rm -rf $dte	
 	ls

	# ARRISXB3-2544 :
	# It takes too long for the unit to reboot after TFTP is completed.
	# Hence we can upload the logs once the unit boots up. We will flag it before reboot.
	touch $UPLOAD_ON_REBOOT
	#$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "TFTP" "URL" "true"
	cd $curDir
   
}

Crashed_Process_Is=$2
#Call function to upload log files on reboot
if [ -e $HAVECRASH ]
then
    if [ "$Crashed_Process_Is" != "" ]
    then
	    echo "RDKB_REBOOT : Rebooting due to $Crashed_Process_Is PROCESS_CRASH"
    fi

    rm -f $HAVECRASH
fi

if [ "$3" == "wan-stopped" ]
then
	echo "Wan-stopped, take log back up"
	backupAllLogs "$LOG_PATH" "$LOG_BACK_UP_PATH" "cp"
else
	backupLogsonReboot	
fi
#sleep 3

if [ "$1" != "" ]
then
     needReboot=$1
fi

if [ "$needReboot" = "true" ]
then
	rebootFunc
fi

