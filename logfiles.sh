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

source /etc/utopia/service.d/log_env_var.sh
source /etc/utopia/service.d/log_capture_path.sh
source $RDK_LOGGER_PATH/utils.sh 
source /etc/logFiles.properties
#. $RDK_LOGGER_PATH/commonUtils.sh
MAINTENANCE_WINDOW="/tmp/maint_upload"
PATTERN_FILE="/tmp/pattern_file"

RSYNC_RUNNING="/tmp/rsync_running"
RSYNC_WAITING="/tmp/rsync_waiting"

SCP_COMPLETE="/tmp/.scp_done"

if [ -f /etc/device.properties ]
then
    source /etc/device.properties
fi

TELEMETRY_INOTIFY_FOLDER=/telemetry
TELEMETRY_INOTIFY_EVENT="$TELEMETRY_INOTIFY_FOLDER/eventType.cmd"

DCA_COMPLETED="/tmp/.dca_done"
PING_PATH="/usr/sbin"
ARM_LOGS_NVRAM2="/nvram2/logs/ArmConsolelog.txt.0"

MAC=`getMacAddressOnly`
HOST_IP=`getIPAddress`
dt=`date "+%m-%d-%y-%I-%M%p"`
LOG_FILE=$MAC"_Logs_$dt.tgz"

FLUSH_LOG_PATH="/rdklogger/flush_logs.sh"

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

createSysDescr()
{
	#Create sysdecr value
	echo_t "Get all parameters to create sysDescr..."
	description=`dmcli eRT getv Device.DeviceInfo.Description | grep value | cut -f3 -d :`
	hwRevision=`dmcli eRT getv Device.DeviceInfo.HardwareVersion | grep value | cut -f3 -d : | tr -d ' '`
	vendor=`dmcli eRT getv Device.DeviceInfo.Manufacturer | grep value | cut -f3 -d :`
	bootloader=`dmcli eRT getv Device.DeviceInfo.X_CISCO_COM_BootloaderVersion | grep value | cut -f3 -d : | tr -d ' '`

	adswVersion=`dmcli eRT getv Device.DeviceInfo.AdditionalSoftwareVersion | grep value | cut -f3 -d : | tr -d ' '`
	swVersion=`dmcli eRT getv Device.DeviceInfo.SoftwareVersion | grep value | cut -f3 -d : | tr -d ' '` 
	sw_fw_version="$adswVersion"_"$swVersion"

	modelName=`dmcli eRT getv Device.DeviceInfo.ModelName | grep value | cut -f3 -d : | tr -d ' '`
	echo_t "RDKB_SYSDESCR : $description HW_REV: $hwRevision; VENDOR: $vendor; BOOTR: $bootloader; SW_REV: $sw_fw_version; MODEL: $modelName "
	
}

flush_atom_logs()
{
 	ssh root@$ATOM_INTERFACE_IP "/bin/echo 'execTelemetry' > $TELEMETRY_INOTIFY_EVENT" > /dev/null 2>&1
 	local loop=0
	while :
	do
		sleep 10
		loop=$((loop+1))
		if [ -f "$DCA_COMPLETED" ] || [ "$loop" -ge 6 ]
		then
			# Remove the contents of ATOM side log files.
			echo_t "DCA completed or wait for 60 sec is over, flushing ATOM logs"
		        dmcli eRT setv Device.Logging.FlushAllLogs bool true | grep "succeed"
                        if [ 0 -ne $? ]
                        then
                            echo_t "Dmcli command failed to execute, calling rpclient to flush logs"
                            rpcclient  $ATOM_ARPING_IP "$FLUSH_LOG_PATH" &
                        fi
			rm -rf $DCA_COMPLETED	
			break
		fi

	done
	
}

protected_rsync()
{

	destination=$1
	RSYNC_PID=`pidof rsync`
	if [ "$RSYNC_PID" != "" ] && [ -f $RSYNC_RUNNING ] && [ ! -f $RSYNC_WAITING ]; then
		i=0;
		timeout=1;
		echo_t "Already rsync running"
		touch $RSYNC_WAITING
		while [ $i -le 60 ]; do
			RSYNC_PID=`pidof rsync`
			if [ "$RSYNC_PID" == "" ]; then
				timeout=0
				echo_t "rsync running over"
				break
			fi
			i=$((i + 1))
			sleep 1
		done

		if [ $timeout -eq 1 ]; then
			echo_t "killing all rsync"
			killall rsync
		fi

		if [ -f $RSYNC_RUNNING ]; then
			rm $RSYNC_RUNNING
		fi
		nice -n 20 rsync root@$ATOM_IP:$ATOM_LOG_PATH$ATOM_FILE_LIST $destination > /dev/null 2>&1
		sync_res=$?
		if [ "$sync_res" -eq 0 ]
		then
			echo "Sync from ATOM complete"
		else
			echo "Sync from ATOM failed , retrun code is $sync_res"
		fi

		if [ -f $RSYNC_WAITING ]; then
			rm $RSYNC_WAITING
		fi

	elif [ "$RSYNC_PID" == "" ]; then
		touch $RSYNC_RUNNING
		nice -n 20 rsync root@$ATOM_IP:$ATOM_LOG_PATH$ATOM_FILE_LIST $destination > /dev/null 2>&1
		sync_res=$?
		if [ "$sync_res" -eq 0 ]
		then
			echo "Sync from ATOM complete"
		else
			echo "Sync from ATOM failed , retrun code is $sync_res"
		fi
		rm $RSYNC_RUNNING
	fi

}

syncLogs_nvram2()
{

	echo_t "sync logs to nvram2"	
	if [ ! -d "$LOG_SYNC_PATH" ]; then
		#echo "making sync dir"
		mkdir -p $LOG_SYNC_PATH
	fi

	 # Sync ATOM side logs in /nvram2/logs/ folder
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
					protected_rsync $LOG_PATH
#nice -n 20 rsync root@$ATOM_IP:$ATOM_LOG_PATH$ATOM_FILE_LIST $LOG_PATH > /dev/null 2>&1
				else
					echo_t "Ping to ATOM ip falied, not syncing ATOM side logs"
				fi
			else
				echo_t "Ping to ATOM ip falied, not syncing ATOM side logs"
			fi
		fi

        fi

	file_list=`ls $LOG_PATH`

	for file in $file_list
	do
		end_char=`echo $file | grep -o '[^.]*$'` # getting the end char in file name
		#echo "end_char = $end_char"
		# handling the scenario of txt.1 file
		if [ "$end_char" == "1" ]; then
	
			if [ -f $LOG_SYNC_PATH$file ]; then
				continue; # continue if txt.1 is already present in nvram2
			fi

			cp $LOG_PATH$file $LOG_SYNC_PATH$file # Copying txt.1 file directly

			file_name=`echo $file | grep -o '^.*\.'`
			file_name=`echo $file_name'0'`
			#echo "file_name = $file_name"
			file=$file_name # replacing txt.1 with txt.0
			rm $LOG_SYNC_PATH$file # removing txt.0 file so that it will be copied again to nvram2
		fi

		if [ ! -f $LOG_SYNC_PATH$file ];then
		    echo "1" > $LOG_SYNC_PATH$file
		fi

		offset=`sed -n '1p' $LOG_SYNC_PATH$file` # getting the offset
		#echo "offset = $offset for file $LOG_PATH$file"

		tail -n +$offset $LOG_PATH$file >> $LOG_SYNC_PATH$file # appeding the logs to nvram2

		offset=`wc -l $LOG_SYNC_PATH$file | cut -d " " -f1`
		#echo "new offset = $offset for file $LOG_PATH$file"
		sed -i -e "1s/.*/$offset/" $LOG_SYNC_PATH$file # setting new offset
	done

}

backupnvram2logs()
{
	destn=$1
	MAC=`getMacAddressOnly`
	workDir=`pwd`

	#createSysDescr

	if [ ! -d "$destn" ]; then
	   mkdir -p $destn
	else
	   FILE_EXISTS=`ls $destn`
	   if [ "$FILE_EXISTS" != "" ]; then
          	rm -rf $destn*.tgz
	   fi
	fi

        if [ "$atom_sync" = "yes" ]
        then
                 # Remove the contents of ATOM side log files.
#                dmcli eRT setv Device.Logging.FlushAllLogs bool true
		 echo_t "call dca for log processing and then flush ATOM logs"
		 flush_atom_logs &

		 if [ -f "$SCP_COMPLETE" ]; then
		   rm -rf $SCP_COMPLETE
		 fi

		 local loop=0
		 while :
		 do
			if [ -f "$SCP_COMPLETE" ] || [ "$loop" -ge 3 ]
			then
				echo_t "scp completed or wait for 30 sec is over"
				if [ -f "$SCP_COMPLETE" ]; then
				  rm -rf $SCP_COMPLETE
				fi
				break
			fi
			loop=$((loop+1))
			sleep 10
		 done
        else
			sh /lib/rdk/dca_utility.sh 2 &
			local loop=0
			while :
			do
				sleep 10
				loop=$((loop+1))
				if [ -f "$DCA_COMPLETED" ] || [ "$loop" -ge 6 ]
				then
					# Remove the contents of ATOM side log files.
					#echo_t "DCA completed or wait for 60 sec is over, flushing ATOM logs"
					#dmcli eRT setv Device.Logging.FlushAllLogs bool true
					rm -rf $DCA_COMPLETED
					break
				fi

			done

        fi

	cd $destn
        if [ -f "/version.txt" ]
        then
	    cp /version.txt $LOG_SYNC_PATH
        else
	   cp /fss/gw/version.txt $LOG_SYNC_PATH
        fi
	echo "*.tgz" > $PATTERN_FILE # .tgz should be excluded while tar
	wan_event=`sysevent get wan_event_log_upload`
        if [ -f "/tmp/.uploadregularlogs" ] || [ "$wan_event" == "yes" ]
        then
		dt=`date "+%m-%d-%y-%I-%M%p"`
	        tar -X $PATTERN_FILE -cvzf $MAC"_Logs_$dt.tgz" $LOG_SYNC_PATH
        fi

	rm $PATTERN_FILE
	 # Removing ATOM side logs

	rm -rf $LOG_SYNC_PATH*.txt*
	rm -rf $LOG_SYNC_PATH*.log
	rm -rf $LOG_SYNC_PATH*core*

	cd $LOG_PATH
	FILES=`ls`

	for fname in $FILES
	do
		>$fname;
	done

	cd $workDir
}

backupnvram2logs_on_reboot()
{
	destn=$1
	MAC=`getMacAddressOnly`
	workDir=`pwd`

	createSysDescr >> $ARM_LOGS_NVRAM2

#	if [ ! -d "$destn" ]; then
#	   mkdir -p $destn
#	else
#	   FILE_EXISTS=`ls $destn`
#	   if [ "$FILE_EXISTS" != "" ]; then
#          	rm -rf $destn*.tgz
#	   fi
#	fi

	cd $destn
        if [ -f "/version.txt" ]
        then
	    cp /version.txt $LOG_SYNC_PATH
        else
	   cp /fss/gw/version.txt $LOG_SYNC_PATH
        fi
	rm -rf *.tgz
	echo "*.tgz" > $PATTERN_FILE # .tgz should be excluded while tar
	dt=`date "+%m-%d-%y-%I-%M%p"`
	tar -X $PATTERN_FILE -cvzf $MAC"_Logs_$dt.tgz" $LOG_SYNC_PATH
	rm $PATTERN_FILE
	rm -rf $LOG_SYNC_PATH*.txt*
	rm -rf $LOG_SYNC_PATH*.log
	rm -rf $LOG_SYNC_PATH*core*

	cd $workDir
}

backupAllLogs()
{
	source=$1
	destn=$2
	operation=$3
	MAC=`getMacAddressOnly`

	workDir=`pwd`
	
        # MAINTENANCE_WINDOW is flagged by maintenance window upload script so that 
        # we will not print the sysDecr value again
        if [ ! -f "$MAINTENANCE_WINDOW" ]
        then
          # Put system descriptor string in log file
	  createSysDescr
        else
           rm -rf $MAINTENANCE_WINDOW
        fi

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
					protected_rsync $LOG_PATH
#nice -n 20 rsync root@$ATOM_IP:$ATOM_LOG_PATH$ATOM_FILE_LIST $LOG_PATH > /dev/null 2>&1
					# dmcli eRT setv Device.Logging.FlushAllLogs bool true
					echo_t "Call dca for log processing and then flush ATOM logs"
					flush_atom_logs &
					 
				else
					echo_t "Ping to ATOM ip falied, not syncing ATOM side logs"
				fi
			else
				echo_t "Ping to ATOM ip falied, not syncing ATOM side logs"
			fi
		fi

	fi	
	cd $destn
	dt=`date "+%m-%d-%y-%I-%M%p"`
	mkdir $dt

	# Check all files in source folder rather just the main log files
	SOURCE_FILES=`ls $source`

	for fname in $SOURCE_FILES
	do
		$operation $source$fname $dt; >$source$fname;
	done
	cp /version.txt $dt

	echo "*.tgz" > $PATTERN_FILE # .tgz should be excluded while tar
	tar -X $PATTERN_FILE -cvzf $MAC"_Logs_$dt.tgz" $dt
	rm $PATTERN_FILE
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
    if [ ! -d $NVRAM_LOG_PATH ]; then
	#echo "making directory"
	mkdir -p $NVRAM_LOG_PATH  # used by no nvram2 device
    fi
    #result=`allFileExists $LOG_PATH`
    #if [ "$result" = "no" ]
    #then
    #return

    file_list=`ls $LOG_PATH`

    for file in $file_list
    do
	cp $LOG_PATH$file $NVRAM_LOG_PATH # Copying all log files directly
    done
    for fname in $LOG_FILES_NAMES
    do
	if [ -f $LOG_PATH$fname ]
   	then
   		cat $LOG_PATH$fname >> $LOG_BACK_UP_REBOOT$fname
   	fi

    #    if [ -f $LOG_BACK_UP_REBOOT$fname ]
	#then
	#	$LOG_BACK_UP_REBOOT$fname > $LOG_PATH$fname
	#fi
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
  echo_t "Done Log Backup"
}

processDCMResponse()
{

    if [ -f "$DCMRESPONSE" ] 
    then
	
		 cp $DCMRESPONSE $DCMRESPONSE_TMP

        	# Start pre-processing the original file
		sed -i 's/,"urn:/\n"urn:/g' $DCMRESPONSE_TMP # Updating the file by replacing all ',"urn:' with '\n"urn:'
		sed -i 's/^{//g' $DCMRESPONSE_TMP # Delete first character from file '{'
		sed -i 's/}$//g' $DCMRESPONSE_TMP # Delete first character from file '}'
		echo "" >> $DCMRESPONSE_TMP         # Adding a new line to the file
		# Start pre-processing the original file

		UPLOAD_LOGS=""
		while read line
		do
		    # Special processing for telemetry
		   #  echo "line = $line"
		    Check_For_Log_Upload_Setting=`echo "$line" | grep  "LogUploadSettings:upload"`
		    if [ "$Check_For_Log_Upload_Setting" != "" ];then
				UPLOAD_LOGS=`echo "$line" | awk -F ":" '{print $NF}'`
                                if [ "$UPLOAD_LOGS" = "" ]
                                then
                                     UPLOAD_LOGS="true"
                                fi
				sysevent set UPLOAD_LOGS_VAL_DCM $UPLOAD_LOGS
				touch $DCM_SETTINGS_PARSED
				echo "$UPLOAD_LOGS"
				break		
		    fi
		done < $DCMRESPONSE_TMP	

		if [ "$UPLOAD_LOGS" = "" ]
		then
                    UPLOAD_LOGS="true"
                    sysevent set UPLOAD_LOGS_VAL_DCM $UPLOAD_LOGS
                    touch $DCM_SETTINGS_PARSED
                    echo "$UPLOAD_LOGS"
		fi

 
    fi
}
