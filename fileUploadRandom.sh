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
source $RDK_LOGGER_PATH/logfiles.sh

if [ -f /etc/device.properties ]
then
    source /etc/device.properties
fi
MAINTENANCEWINDOW="/tmp/maint_upload"

TELEMETRY_INOTIFY_FOLDER=/telemetry
TELEMETRY_INOTIFY_EVENT="$TELEMETRY_INOTIFY_FOLDER/eventType.cmd"

CRON_TAB="/var/spool/cron/crontabs/root"
DCM_PATH="/lib/rdk"
SELFHEAL_PATH="/usr/ccsp/tad"

calcRandTimeandUpload()
{
    rand_hr=0
    rand_min=0
    rand_sec=0

    # Calculate random min
    rand_min=`awk -v min=0 -v max=59 -v seed="$(date +%N)" 'BEGIN{srand(seed);print int(min+rand()*(max-min+1))}'`

    # Calculate random second
    rand_sec=`awk -v min=0 -v max=59 -v seed="$(date +%N)" 'BEGIN{srand(seed);print int(min+rand()*(max-min+1))}'`
        
    # Calculate random hour
    rand_hr=`awk -v min=0 -v max=2 -v seed="$(date +%N)" 'BEGIN{srand(seed);print int(min+rand()*(max-min+1))}'`

    echo_t "RDK Logger : Random Time Generated : $rand_hr hr $rand_min min $rand_sec sec"
	
    min_to_sleep=$(($rand_hr*60 + $rand_min))
    sec_to_sleep=$(($min_to_sleep*60 + $rand_sec))
    sleep $sec_to_sleep;
   
    if [ -f "$MAINTENANCEWINDOW" ]
    then
        rm -rf $MAINTENANCEWINDOW
    fi
    
    # Create sys descriptor before log sync and upload
    createSysDescr
    touch $MAINTENANCEWINDOW

    # Telemetry data should be sent before log upload 
    echo_t "RDK Logger : Process Telemetry logs before log upload.."

    if [ "$DCA_MULTI_CORE_SUPPORTED" = "yes" ]
    then
        ssh root@$ATOM_INTERFACE_IP "/bin/echo 'execTelemetry' > $TELEMETRY_INOTIFY_EVENT" > /dev/null 2>&1
        # This delay is to make sure that scp of all files from ARM to ATOM is done
        sleep 30
    else
        CMD=`cat $CRON_TAB | grep dca_utility | sed -e "s|.* sh|sh|g"`

        if [ "$CMD" != "" ]
        then
           echo_t "RDK Logger : Telemetry command received is #$CMD"
           $CMD &

           # We have slept enough, have a sleep of 1 more minute.
           # We do not know at what time telemetry script parses the script
           # let's put this 60 sec sleep
           sleep 60
        else
           echo_t "RDK Logger : DCA cron job is not configured"
        fi
    fi
    # Check if nvram2 log back up is enabled
    nvram2Backup="false"
    backupenabled=`syscfg get logbackup_enable`
    nvram2Supported="no"
    
    if [ -f /etc/device.properties ]
    then
       nvram2Supported=`echo $NVRAM2_SUPPORTED`
    fi

    if [ "$nvram2Supported" = "yes" ] && [ "$backupenabled" = "true" ]
    then
	nvram2Backup="true"
    else
        nvram2Backup="false"
    fi

    echo_t "RDK Logger : Trigger Maintenance Window log upload.."

    UPLOAD_LOGS=`sysevent get UPLOAD_LOGS_VAL_DCM`
    if [ "$UPLOAD_LOGS" = "" ] || [ ! -f "$DCM_SETTINGS_PARSED" ]
    then
    	echo_t "processDCMResponse to get the logUploadSettings"
	UPLOAD_LOGS=`processDCMResponse`
    fi
    echo_t "UPLOAD_LOGS val is $UPLOAD_LOGS"
    
    if [ "$UPLOAD_LOGS" = "true" ] || [ "$UPLOAD_LOGS" = "" ]		
    then
        UPLOAD_LOGS="true"
        if [ ! -f "/tmp/.uploadregularlogs" ]
        then
            echo_t "Log upload is enabled. Touching indicator in maintenance window"         
            touch /tmp/.uploadregularlogs
        fi
    else
        echo_t "Log upload is disabled. Removing indicator in maintenance window"         
        rm -rf /tmp/.uploadregularlogs
    fi

    if [ "$nvram2Backup" == "true" ]; then
       syncLogs_nvram2	
       backupnvram2logs "$LOG_SYNC_BACK_UP_PATH"
    else
       syncLogs
       backupAllLogs "$LOG_PATH" "$LOG_BACK_UP_PATH" "cp"
    fi


    if [ "$UPLOAD_LOGS" =  "true" ]
    then
	    $RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false"
    else
	    echo_t "Log upload is disabled in maintenance window"         
    fi

    upload_logfile=0
    
    echo_t "RDKB_MEM_HEALTH : Check device memory health"
    sh $SELFHEAL_PATH/check_memory_health.sh
    
    # RDKB-6095 : DCM service should sync with XCONF daily on 
    # the maintenance window
    if [ -f $DCM_PATH/dcm.service ]; 
    then
        echo_t "RDK Logger : Run DCM service"
	if [ -f "$DCM_SETTINGS_PARSED" ]
	then
		rm -rf $DCM_SETTINGS_PARSED
	fi
	 sh $DCM_PATH/dcm.service &
    else
        echo_t "RDK Logger : No DCM service file"
    fi

    createSysDescr
}


## Identifies whether it is a VBN or PROD build
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

getTFTPServer()
{
        if [ "$1" != "" ]
        then
		logserver=`cat $RDK_LOGGER_PATH/dcmlogservers.txt | grep $1 | cut -f2 -d"|"`
		echo $logserver
	fi
}


BUILD_TYPE=`getBuildType`
SERVER=`getTFTPServer $BUILD_TYPE`
loop=1
upload_logfile=1
while [ $loop -eq 1 ]
do
    sleep 60

	if [ "$UTC_ENABLE" == "true" ]
	then
		cur_hr=`LTime H`
		cur_min=`LTime M`
	else
		cur_hr=`date +"%H"`
		cur_min=`date +"%M"`
	fi

	if [ "$cur_hr" -ge 02 ] && [ "$cur_hr" -le 05 ]
	then
      	     if [ "$cur_hr" -eq 05 ] && [ "$cur_min" -ne 00 ]
	     then
		   upload_logfile=1		
	     else
	  	   if [ "$upload_logfile" -eq 1 ]
		   then	
	 	         calcRandTimeandUpload
	   	   fi
	     fi
	else
		upload_logfile=1
	fi
done

