#!/bin/sh

source /fss/gw/etc/utopia/service.d/log_env_var.sh
source /etc/utopia/service.d/log_capture_path.sh
source $RDK_LOGGER_PATH/utils.sh 
#. $RDK_LOGGER_PATH/commonUtils.sh



TR69Log="TR69log.txt.0"
TR69LogsBackup="TR69log.txt.1"

PAMLog="PAMlog.txt.0"
PAMLogsBackup="PAMlog.txt.1"

PSMLog="PSMlog.txt.0"
PSMLogsBackup="PSMlog.txt.1"

CRLog="CRlog.txt.0"
CRLogsBackup="CRlog.txt.1"

MTALog="MTAlog.txt.0"
MTALogsBackup="MTAlog.txt.1"

FULog="FUlog.txt.0"
FULogsBackup="FUlog.txt.1"

CMLog="CMlog.txt.0"
CMLogsBackup="CMlog.txt.1"

TDMLog="TDMlog.txt.0"
TDMLogsBackup="TDMlog.txt.1"

WiFiLog="WiFilog.txt.0"
WiFiLogsBackup="WiFilog.txt.1"

ConsoleLog="Consolelog.txt.0"
ConsoleLogsBackup="Consolelog2.txt.0"

ArmConsoleLog="ArmConsolelog.txt.0"
ArmConsoleLogsBackup="ArmConsolelog.txt.0"

XconfLog="xconf.txt.0"
XconfLogsBackup="xconf.txt.0"

LMLog="LM.txt.0"
LMLogsBackup="LM.txt.1"

SNMPLog="SNMP.txt.0"
SNMPLogsBackup="SNMP.txt.1"

LighttpdAccessLog="lighttpdaccess.log"
LighttpdAccessLogsBackup="lighttpdaccess.log"

LighttpdErrorLog="lighttpderror.log"
LighttpdErrorLogsBackup="lighttpderror.log"

HotspotLog="Hotspotlog.txt.0"
HotspotLogsBackup="Hotspotlog.txt.1"

DhcpSnoopLog="Dhcpsnooplog.txt.0"
DhcpSnoopLogsBackup="Dhcpsnooplog.txt.1"

MiscLog="Misc.txt.0"

MAC=`getMacAddressOnly`
HOST_IP=`getIPAddress`
dte=`date "+%m-%d-%y-%I-%M%p"`
LOG_FILE=$MAC"_Logs_$dt.tgz"

LOG_FILES_NAMES="$TR69Log $PAMLog $PSMLog $CRLog $MTALog $FULog $TDMLog $CMLog $WiFiLog $MiscLog $ConsoleLog $XconfLog $LMLog $SNMPLog $ArmConsoleLog $LighttpdAccessLog $LighttpdErrorLog $HotspotLog $DhcpSnoopLog"

moveFile()
{        
     if [[ -f "$1" ]]; then mv $1 $2; fi
}
 
moveFiles()
{
# $1 : source folder
# $2 : destination folder

     currentDir=`pwd`
     cd $2
     
     mv $1/* .
     
     cd $currentDir
}

createFiles()
{
	FILES=$LOG_FILES_NAMES
	for f in $FILES
	do
		if [ ! -e $LOGTEMPPATH$f ]
		then
			touch $LOGTEMPPATH$f
		fi
	done
	touch $LOG_FILE_FLAG
}


backupAllLogs()
{
	source=$1
	destn=$2
	operation=$3
	MAC=`getMacAddressOnly`

	dt=`date "+%m-%d-%y-%I-%M%p"`
	workDir=`pwd`
	
	if [ ! -d "$destn" ]
	then

	   mkdir -p $destn
	else
	   FILE_EXISTS=`ls $destn`
	   if [ "$FILE_EXISTS" != "" ]
       	   then
          	rm -rf $LOG_BACK_UP_PATH*
	   fi
	fi	
	
	cd $destn
	mkdir $dt

	# Check all files in source folder rather just the main log files
	SOURCE_FILES=`ls $source`

	for fname in $SOURCE_FILES
	do
		$operation $source$fname $dt; >$source$fname;
	done
    cp /fss/gw/version.txt $dt
	tar -cvzf $MAC"_Logs_$dt.tgz" $dt
	
 	rm -rf $dt
	cd $workDir
}

rotateLogs()
{

	fileName=$1
	if [ ! -d $LOGTEMPPATH ]
	then
		mkdir -p $LOGTEMPPATH
	fi
	
	if [ ! -e $LOGTEMPPATH$fileName ]
	then
		touch $LOGTEMPPATH$fileName
	fi
	#ls $LOGTEMPPATH

	cat $LOG_PATH$fileName >> $LOGTEMPPATH$fileName
	#echo "" > $LOG_PATH$fileName
    >$LOG_PATH$fileName
}

allFileExists()
{
   source=$1
   local fileMissing=0
   for fname in $LOG_FILES_NAMES
   do
   	if [ ! -f $source$fname ]
   	then
   	    fileMissing=1
   	fi
   done

   if [ $fileMissing -eq 1 ]
   then
       echo "no"
   else
       echo "yes"
   fi
   
}

syncLogs()
{
    #result=`allFileExists $LOG_PATH`
    #if [ "$result" = "no" ]
    #then
	    #return
    for fname in $LOG_FILES_NAMES
    do
	if [ -f $LOG_PATH$fname ]
   	then
   		cat $LOG_PATH$fname >> $LOG_BACK_UP_REBOOT$fname
   	fi

        if [ -f $LOG_BACK_UP_REBOOT$fname ]
	then
		$LOG_BACK_UP_REBOOT$fname > $LOG_PATH$fname
	fi
   done
    #fi
	
	#for fname in $LOG_FILES_NAMES
	#do
	#    	cat $LOG_PATH$fname >> $LOG_BACK_UP_REBOOT$fname
	#done
	
	#moveFiles $LOG_BACK_UP_REBOOT $LOG_PATH
	#rm -rf $LOG_BACK_UP_REBOOT
}


logCleanup()
{
  rm $LOG_PATH/*
  rm $LOG_BACK_UP_PATH/*
  echo "Done Log Backup"
}
