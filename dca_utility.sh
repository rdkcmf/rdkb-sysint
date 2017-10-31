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

. /etc/include.properties
. /etc/device.properties


if [ -f /lib/rdk/utils.sh  ]; then
   . /lib/rdk/utils.sh
fi
source /etc/log_timestamp.sh
EROUTER_IF=erouter0
DCMRESPONSE="$PERSISTENT_PATH/DCMresponse.txt"
DCM_SETTINGS_CONF="/tmp/DCMSettings.conf"

TELEMETRY_PATH="$PERSISTENT_PATH/.telemetry"
TELEMETRY_PATH_TEMP="$TELEMETRY_PATH/tmp"
TELEMETRY_PROFILE_PATH="$PERSISTENT_PATH/.DCMSettings.conf"
LOG_SYNC_PATH="/nvram2/logs/"

RTL_LOG_FILE="$LOG_PATH/dcmProcessing.log"
RTL_DELTA_LOG_FILE="$RAMDISK_PATH/.rtl_temp.log"
PATTERN_CONF_FILE="$TELEMETRY_PATH/dca.conf"
MAP_PATTERN_CONF_FILE="$TELEMETRY_PATH/dcafile.conf"
TEMP_PATTERN_CONF_FILE="$TELEMETRY_PATH/temp_dcafile.conf"
EXEC_COUNTER_FILE="/tmp/.dcaCounter.txt"

# Persist this files for telemetry operation
# Regenerate this only when there is a change identified from XCONF update
SORTED_PATTERN_CONF_FILE="$TELEMETRY_PATH/dca_sorted_file.conf"

current_cron_file="$PERSISTENT_PATH/cron_file.txt"

OUTPUT_FILE="$LOG_PATH/dca_output.txt"

#Performance oriented binaries
TEMPFILE_CREATER_BINARY="/usr/bin/dcaseek"
TEMPFILE_PARSE_BINARY="/usr/bin/dcafind"
PERFORMANCE_BINARY="/usr/bin/dcaprocess"
LOAD_AVG_BINARY="/usr/bin/dcaloadave"
IPVIDEO_BINARY="/usr/bin/ipvideo"

TELEMETRY_INOTIFY_FOLDER=/telemetry
TELEMETRY_INOTIFY_EVENT="$TELEMETRY_INOTIFY_FOLDER/eventType.cmd"
TELEMETRY_EXEC_COMPLETE="/tmp/.dca_done"
SCP_COMPLETE="/tmp/.scp_done"
PEER_COMM_DAT="/etc/dropbear/elxrretyt.swr"
PEER_COMM_ID="/tmp/elxrretyt-$$.swr"
CONFIGPARAMGEN="/usr/bin/configparamgen"

if [ "x$DCA_MULTI_CORE_SUPPORTED" = "xyes" ]; then
    CRON_SPOOL=/tmp/cron
    if [ -f /etc/logFiles.properties ]; then
        . /etc/logFiles.properties
    fi
    
fi


# Retain source for future enabling. Defaulting to disable for now
snmpCheck=false

# exit if an instance is already running
if [ ! -f /tmp/.dca-utility.pid ];then
    # store the PID
    echo $$ > /tmp/.dca-utility.pid
else
    pid=`cat /tmp/.dca-utility.pid`
    if [ -d /proc/$pid ];then
	  exit 0
    else
	  echo $$ > /tmp/.dca-utility.pid
    fi
fi

if [ "$LIGHTSLEEP_ENABLE" == "true" ] && [ -f /tmp/.standby ]; then
    pidCleanup
    exit 0
fi

mkdir -p $LOG_PATH
touch $RTL_LOG_FILE

if [ ! -f /tmp/.dca_bootup ]; then
   echo_t "First dca execution after bootup. Clearing all markers." >> $RTL_LOG_FILE
   touch /tmp/.dca_bootup
   rm -rf $TELEMETRY_PATH
   rm -f $RTL_LOG_FILE
fi


PrevFileName=''

#Adding support for opt override for dcm.properties file
if [ "$BUILD_TYPE" != "prod" ] && [ -f $PERSISTENT_PATH/dcm.properties ]; then
      . $PERSISTENT_PATH/dcm.properties
else
      . /etc/dcm.properties
fi


if [ ! -d "$TELEMETRY_PATH_TEMP" ]
then
    echo "Telemetry Folder does not exist . Creating now" >> $RTL_LOG_FILE
    mkdir -p "$TELEMETRY_PATH_TEMP"
else
    cp $TELEMETRY_PATH/rtl_* $TELEMETRY_PATH_TEMP/
fi

mkdir -p $TELEMETRY_PATH

pidCleanup()
{
   # PID file cleanup
   if [ -f /tmp/.dca-utility.pid ];then
        rm -rf /tmp/.dca-utility.pid
   fi
}

if [ $# -ne 1 ]; then
   echo "Usage : `basename $0` <0/1/2> 0 - Telemtry From Cron 1 - Reinitialize Map 2 - Forced Telemetry search " >> $RTL_LOG_FILE
   pidCleanup
   exit 0
fi

# 0 if as part of normal execution
# 1 if initiated due to an XCONF update
# 2 if forced execution before log upload
# 3 if modify the cron schedule 

triggerType=$1
echo_t "dca: Trigger type is $triggerType" >> $RTL_LOG_FILE

cd $LOG_PATH


isNum()
{
    Number=$1
    if [ $Number -ne 0 -o $Number -eq 0 2>/dev/null ];then
        echo 0
    else
        echo 1
    fi
}

# Function to get partner_id
getPartnerId()
{
    if [ -f "/etc/device.properties" ]
    then
        partner_id=`cat /etc/device.properties | grep PARTNER_ID | cut -f2 -d=`
        if [ "$partner_id" == "" ];then
            #Assigning default partner_id as Comcast.
            #If any device want to report differently, then PARTNER_ID flag has to be updated in /etc/device.properties accordingly
            echo "comcast"
        else
            echo "$partner_id"
        fi
    else
       echo "null"
    fi
}

# Function to get erouter0 ipv4 address
getErouterIpv4()
{
    if [ -e  /usr/sbin/deviceinfo.sh ]; then
        #On ATOM get IP from deviceInfo
        erouter_ipv4=`/usr/sbin/deviceinfo.sh  -eip`
    else
        erouter_ipv4=`ifconfig erouter0 | grep "inet addr" | grep -v inet6 | cut -f2 -d: | cut -f1 -d" "`
    fi

    if [ "$erouter_ipv4" != "" ];then
        echo $erouter_ipv4
    else
        echo "null"
    fi
}

# Function to get erouter0 ipv6 address
getErouterIpv6()
{
    if [ -e  /usr/sbin/deviceinfo.sh ]; then
        erouter_ipv6=`/usr/sbin/deviceinfo.sh  -eipv6`
    else
        erouter_ipv6=`ifconfig erouter0 | grep inet6 | tr -s " " | grep -v Link | cut -d " " -f4 | cut -d "/" -f1`
    fi

    if [ "$erouter_ipv6" != "" ];then
        echo $erouter_ipv6
    else
        echo "null"
    fi
}

getSNMPUpdates() {
     snmpMIB=$1
     TotalCount=0
     export MIBS=ALL
     export MIBDIRS=/mnt/nfs/bin/target-snmp/share/snmp/mibs:/usr/share/snmp/mibs
     export PATH=$PATH:/mnt/nfs/bin/target-snmp/bin
     export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/mnt/nfs/bin/target-snmp/lib:/mnt/nfs/usr/lib
     snmpCommunityVal=`head -n 1 /tmp/snmpd.conf | awk '{print $4}'`
     tuneString=`snmpwalk  -OQv -v 2c -c $snmpCommunityVal 127.0.0.1 $snmpMIB`
     for count in $tuneString
     do
         count=`echo $count | tr -d ' '`
         if [ $(isNum $count) -eq 0 ]; then
            TotalCount=`expr $TotalCount + $count`
         else
            TotalCount=$count
         fi
     done
     
     echo $TotalCount
}

# Function to get performance values 
getPerformanceValue() {
     process_name=$1
     performance_value=''
     performance_value=`nice -n 19 $PERFORMANCE_BINARY $process_name`
     echo $performance_value
}

# Function to get performance values 
getLoadAverage() {
     load_average=''
     load_average=`nice -n 19 $LOAD_AVG_BINARY`
     echo $load_average
}

## Reatining for future support when net-snmp tools will be enabled in XB3s
getControllerId(){    
    ChannelMapId=''
    ControllerId=''
    VctId=''
    vodServerId=''
    export MIBS=ALL
    export MIBDIRS=/mnt/nfs/bin/target-snmp/share/snmp/mibs:/usr/share/snmp/mibs
    export PATH=$PATH:/mnt/nfs/bin/target-snmp/bin
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/mnt/nfs/bin/target-snmp/lib:/mnt/nfs/usr/lib
    
    snmpCommunityVal=`head -n 1 /tmp/snmpd.conf | awk '{print $4}'`
    ChannelMapId=`snmpwalk -OQ -v 2c -c $snmpCommunityVal 127.0.0.1 1.3.6.1.4.1.17270.9225.1.1.40 | awk -F '= ' '{print $2}'`
    ControllerId=`snmpwalk -OQ -v 2c -c $snmpCommunityVal 127.0.0.1 1.3.6.1.4.1.17270.9225.1.1.41 | awk -F '= ' '{print $2}'`  
    VctId=`snmpwalk -OQ -v 2c -c $snmpCommunityVal 127.0.0.1 OC-STB-HOST-MIB::ocStbHostCardVctId.0 | awk -F '= ' '{print $2}'`
    vodServerId=`snmpwalk -OQ -v 2c -c $snmpCommunityVal 127.0.0.1 1.3.6.1.4.1.17270.9225.1.1.43 | awk -F '= ' '{print $2}'`
    
    echo "{\"ChannelMapId\":\"$ChannelMapId\"},{\"ControllerId\":\"$ControllerId\"},{\"VctId\":$VctId},{\"vodServerId\":\"$vodServerId\"}"    
}

# Function to get RF status
## Reatining for future support when net-snmp tools will be enabled in XB3s
getRFStatus(){
    Dwn_RX_pwr=''
    Ux_TX_pwr=''
    Dx_SNR=''
    export MIBS=ALL
    export MIBDIRS=/mnt/nfs/bin/target-snmp/share/snmp/mibs
    export PATH=$PATH:/mnt/nfs/bin/target-snmp/bin
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/mnt/nfs/bin/target-snmp/lib:/mnt/nfs/usr/lib
    
    snmpCommunityVal=`head -n 1 /tmp/snmpd.conf | awk '{print $4}'`
    Dwn_RX_pwr=`snmpwalk -OQ -v 2c -c $snmpCommunityVal 192.168.100.1 DOCS-IF-MIB::docsIfDownChannelPower.3 | awk -F '= ' '{print $2}'`
    Ux_TX_pwr=`snmpwalk -OQ -v 2c -c $snmpCommunityVal 192.168.100.1 DOCS-IF-MIB::docsIfCmStatusTxPower.2 | awk -F '= ' '{print $2}'`  
    Dx_SNR=`snmpwalk -OQ -v 2c -c $snmpCommunityVal 192.168.100.1 DOCS-IF-MIB::docsIfSigQSignalNoise.3 | awk -F '= ' '{print $2}'`
    
    echo "{\"Dwn_RX_pwr\":\"$Dwn_RX_pwr\"},{\"Ux_TX_pwr\":\"$Ux_TX_pwr\"},{\"Dx_SNR\":\"$Dx_SNR\"}"
}

###
##  Dumps deltas from previous execution to file /tmp/.rtl_temp.log
##  Get the number of occurence of pattern from the deltas to avoid duplicate error report
##  Append the results to OUTPUT_FILE ie LOG_PATHdca_output.txt
###    
updateCount()
{
    final_count=0
    # Need not create the dela file is the previous file in MAP is the same 
    if [ "$filename" != "$PrevFileName" ]; then    
       PrevFileName=$filename
       if [ -f "$TELEMETRY_PATH_TEMP/rtl_$filename" ]; then
           lastSeekVal=`cat $TELEMETRY_PATH_TEMP/rtl_$filename`
       else
           lastSeekVal=0
       fi
       rm -f $RTL_DELTA_LOG_FILE
       nice -n 19 $TEMPFILE_CREATER_BINARY $filename
       seekVal=`cat $TELEMETRY_PATH_TEMP/rtl_$filename`
       if [ $seekVal -lt $lastSeekVal ]; then
           # This should never happen in RDKB as we don't have log rotation
           # Instead upload & flush logs are present which is already taken care
           echo_t "dca seek value for $filename is Previous : $lastSeekVal Current : $seekVal" >> $RTL_LOG_FILE   
           echo "Restoring markers" >> $RTL_LOG_FILE   
           # Can be due to rsync/scp errors. Restore previous well known markers
           echo "$lastSeekVal" > $TELEMETRY_PATH_TEMP/rtl_$filename
       fi
    fi

    header=`grep -F "$pattern<#=#>$filename" $MAP_PATTERN_CONF_FILE | head -n 1 | awk -F '<#=#>' '{print $1}'`
    isSkip="true"
    if [ $skipInterval -eq 0 ] || [ $dcaNexecCounter -eq 0 ]; then
        isSkip="false"
    else
        skipInterval=`expr $skipInterval + 1`
        execModulusVal=0
        if [ $dcaNexecCounter -lt $skipInterval ]; then
            isSkip="true"
        else
            execModulusVal=$(($dcaNexecCounter % $skipInterval))
            if [ $execModulusVal -eq 0 ]; then
                isSkip="false"
            fi
        fi
    fi
    final_count=""

    if [ "$isSkip" == "false" ]; then
        case "$header" in
            *split*)  
	     final_count=`nice -n 19 $IPVIDEO_BINARY $RTL_DELTA_LOG_FILE "$pattern"` ;;
	    *) 
	     final_count=`nice -n 19 $TEMPFILE_PARSE_BINARY $RTL_DELTA_LOG_FILE "$pattern" | awk -F '=' '{print $NF}'` ;;
        esac
    fi
    # Update count and patterns in a single file 
    if [ ! -z "$final_count" ] && [ "$final_count" != "0" ]; then
       echo "$pattern<#=#>$filename<#=#>$final_count" >> $OUTPUT_FILE
    fi
}     

processJsonResponse()
{
    FILENAME=$1
    #Condider getting the filename as an argument instead of using global file name
    if [ -f "$FILENAME" ]; then
        # Start pre-processing the original file
        sed -i 's/,"urn:/\n"urn:/g' $FILENAME # Updating the file by replacing all ',"urn:' with '\n"urn:'
        sed -i 's/^{//g' $FILENAME # Delete first character from file '{'
        sed -i 's/}$//g' $FILENAME # Delete first character from file '}'
        echo "" >> $FILENAME         # Adding a new line to the file
        # Start pre-processing the original file

        OUTFILE=$DCM_SETTINGS_CONF
        OUTFILEOPT="$PERSISTENT_PATH/.DCMSettings.conf"
        #rm -f $OUTFILE #delete old file
        cat /dev/null > $OUTFILE #empty old file
        cat /dev/null > $OUTFILEOPT
        while read line
        do
            # Special processing for telemetry
            profile_Check=`echo "$line" | grep -ci 'TelemetryProfile'`
            if [ $profile_Check -ne 0 ];then
                #echo "$line"
                echo "$line" | sed 's/"header":"/"header" : "/g' | sed 's/"content":"/"content" : "/g' | sed 's/"type":"/"type" : "/g' >> $OUTFILE

                echo "$line" | sed 's/"header":"/"header" : "/g' | sed 's/"content":"/"content" : "/g' | sed 's/"type":"/"type" : "/g' | sed -e 's/uploadRepository:URL.*","//g'  >> $OUTFILEOPT
            else
                echo "$line" | sed 's/":/=/g' | sed 's/"//g' >> $OUTFILE
            fi
        done < $FILENAME
    else
        echo "$FILENAME not found." >> $RTL_LOG_FILE
        return 1
    fi
}

scheduleCron()
{
    cron=''
    scheduler_Check=`grep '"schedule":' $DCM_SETTINGS_CONF`
    if [ -n "$scheduler_Check" ]; then
        cron=`cat $DCM_SETTINGS_CONF | grep -i TelemetryProfile | awk -F '"schedule":' '{print $NF}' | awk -F "," '{print $1}' | sed 's/://g' | sed 's/"//g' | sed -e 's/^[ ]//' | sed -e 's/^[ ]//'`
    fi

	#During diagnostic mode need to apply the cron schedule value through this custom configuraion 
	DiagnosticMode=`dmcli eRT getv Device.SelfHeal.X_RDKCENTRAL-COM_DiagnosticMode | grep value | cut -f3 -d : | cut -f2 -d" "`
	if [ "$DiagnosticMode" == "true" ];then
	LogUploadFrequency=`dmcli eRT getv Device.SelfHeal.X_RDKCENTRAL-COM_DiagMode_LogUploadFrequency | grep value | cut -f3 -d : | cut -f2 -d" "`
		if [ "$LogUploadFrequency" != "" ]; then
			cron=''
			cron="*/$LogUploadFrequency * * * *"
			echo_t "dca: the default Cron schedule from XCONF is ignored and instead SNMP overriden value is used" >> $RTL_LOG_FILE
		fi
	fi	

	#Check whether cron having empty value if it is empty then need to assign 
	#15mins by default
	if [ -z "$cron" ]; then
		echo_t "dca: Empty cron value so set default as 15mins" >> $RTL_LOG_FILE
		cron="*/15 * * * *"
	fi	

    if [ -n "$cron" ]; then
	# Dump existing cron jobs to a file
	crontab -l -c $CRON_SPOOL > $current_cron_file
	# Check whether any cron jobs are existing or not
	existing_cron_check=`cat $current_cron_file | tail -n 1`
	tempfile="$PERSISTENT_PATH/tempfile.txt"
	rm -rf $tempfile  # Delete temp file if existing
	if [ -n "$existing_cron_check" ]; then
		rtl_cron_check=`grep -c 'dca_utility.sh' $current_cron_file`
		if [ $rtl_cron_check -eq 0 ]; then
			echo "$cron nice -n 19 sh $RDK_PATH/dca_utility.sh 0" >> $tempfile
		fi
		while read line
		do
			retval=`echo "$line" | grep 'dca_utility.sh'`
			if [ -n "$retval" ]; then
				echo "$cron nice -n 19 sh $RDK_PATH/dca_utility.sh 0" >> $tempfile
			else
				echo "$line" >> $tempfile
			fi
		done < $current_cron_file
	else
		# If no cron job exists, create one, with the value from DCMSettings.conf file
		echo "$cron nice -n 19 sh $RDK_PATH/dca_utility.sh 0" >> $tempfile
	fi
	# Set new cron job from the file
	crontab $tempfile -c $CRON_SPOOL
	rm -rf $current_cron_file # Delete temp file
	rm -rf $tempfile          # Delete temp file
    else
	echo " `date` Failed to read \"schedule\" cronjob value from DCMSettings.conf." >> $RTL_LOG_FILE
    fi
}

dropbearRecovery()
{
   dropbearPid=`ps | grep -i dropbear | grep "$ATOM_INTERFACE_IP" | grep -v grep`
   if [ -z "$dropbearPid" ]; then
       dropbear -E -s -p $ATOM_INTERFACE_IP:22 &
       sleep 2
   fi
}
   
clearTelemetryConfig()
{
    if [ -f $RTL_DELTA_LOG_FILE ]; then
        echo_t "dca: Deleting : $RTL_DELTA_LOG_FILE" >> $RTL_LOG_FILE
        rm -f $RTL_DELTA_LOG_FILE
    fi

    if [ -f $PATTERN_CONF_FILE ]; then
        echo_t "dca: PATTERN_CONF_FILE : $PATTERN_CONF_FILE" >> $RTL_LOG_FILE
        rm -f $PATTERN_CONF_FILE
    fi

    if [ -f $MAP_PATTERN_CONF_FILE ]; then
        echo_t "dca: MAP_PATTERN_CONF_FILE : $MAP_PATTERN_CONF_FILE" >> $RTL_LOG_FILE
        rm -f $MAP_PATTERN_CONF_FILE
    fi

    if [ -f $TEMP_PATTERN_CONF_FILE ]; then
        echo_t "dca: TEMP_PATTERN_CONF_FILE : $TEMP_PATTERN_CONF_FILE" >> $RTL_LOG_FILE
        rm -f $TEMP_PATTERN_CONF_FILE
    fi

    if [ -f $SORTED_PATTERN_CONF_FILE ]; then
        echo_t "dca: SORTED_PATTERN_CONF_FILE : $SORTED_PATTERN_CONF_FILE" >> $RTL_LOG_FILE
        rm -f $SORTED_PATTERN_CONF_FILE
    fi

}

## Pass The I/P O/P Files As Arguments
generateTelemetryConfig()
{
    input_file=$1
    output_file=$2
    touch $TEMP_PATTERN_CONF_FILE
    if [ -f $input_file ]; then
      grep -i 'TelemetryProfile' $input_file | sed 's/=\[/\n/g' | sed 's/},/}\n/g' | sed 's/],/\n/g'| sed -e 's/^[ ]//' > $TEMP_PATTERN_CONF_FILE
    fi

  # Create map file from json message file
    while read line
    do         
        header_Check=`echo "$line" | grep -c '{"header"'`
        if [ $header_Check -ne 0 ];then
           polling=`echo "$line" | grep -c 'pollingFrequency'`
           if [ $polling -ne 0 ];then
              header=`echo "$line" | awk -F '"header" :' '{print $NF}' | awk -F '",' '{print $1}' | sed -e 's/^[ ]//' | sed 's/^"//'`
              content=`echo "$line" | awk -F '"content" :' '{print $NF}' | awk -F '",' '{print $1}' | sed -e 's/^[ ]//' | sed 's/^"//'`
              logFileName=`echo "$line" | awk -F '"type" :' '{print $NF}' | awk -F '",' '{print $1}' | sed -e 's/^[ ]//' | sed 's/^"//'`
              skipInterval=`echo "$line" | sed -e "s/.*pollingFrequency\":\"//g" | sed 's/"}//'`
           else
              header=`echo "$line" | awk -F '"header" :' '{print $NF}' | awk -F '",' '{print $1}' | sed -e 's/^[ ]//' | sed 's/^"//'`
              content=`echo "$line" | awk -F '"content" :' '{print $NF}' | awk -F '",' '{print $1}' | sed -e 's/^[ ]//' | sed 's/^"//'`
              logFileName=`echo "$line" | awk -F '"type" :' '{print $NF}' | sed -e 's/^[ ]//' | sed 's/^"//' | sed 's/"}//'`
              #default value to 0
              skipInterval=0
           fi
 
           if [ -n "$header" ] && [ -n "$content" ] && [ -n "$logFileName" ] && [ -n "$skipInterval" ]; then
              echo "$header<#=#>$content<#=#>$logFileName<#=#>$skipInterval" >> $MAP_PATTERN_CONF_FILE
           fi
        fi
    done < $TEMP_PATTERN_CONF_FILE

    #Create conf file from map file
    while read line
    do
        content=`echo "$line" | awk -F '<#=#>' '{print $2}'`
        logFileName=`echo "$line" | awk -F '<#=#>' '{print $3}'`
        skipInterval=`echo "$line" | awk -F '<#=#>' '{print $4}'`
        echo "$content<#=#>$logFileName<#=#>$skipInterval" >> $PATTERN_CONF_FILE
    done < $MAP_PATTERN_CONF_FILE

    # Sort the config file based on file names to minimise the duplicate delta file generation
    if [ -f $PATTERN_CONF_FILE ]; then
        if [ -f $output_file ]; then
            rm -f $output_file
        fi
        awk -F '<#=#>' '{print $NF,$0}' $PATTERN_CONF_FILE | sort -n | cut -d ' ' -f 2- > $output_file 
    fi

}

# Reschedule the cron based on diagnositic mode
if [ $triggerType -eq 3 ] ; then
	echo_t "dca: Processing rescheduleCron job" >> $RTL_LOG_FILE
    scheduleCron
    ## Telemetry must be invoked only for reschedule cron job
    pidCleanup
    exit 0
fi

# Regenerate config only during boot-up and when there is an update
if [ ! -f $SORTED_PATTERN_CONF_FILE ] || [ $triggerType -eq 1 ] ; then
# Start crond daemon for yocto builds
    pidof crond
    if [ $? -ne 0 ]; then
        mkdir -p $CRON_SPOOL
        touch $CRON_SPOOL/root
        crond -c $CRON_SPOOL -l 9
    fi

    if [ "x$DCA_MULTI_CORE_SUPPORTED" = "xyes" ]; then
        while [ ! -f $DCMRESPONSE ]
        do
            echo "WARNING !!! Unable to locate $DCMRESPONSE .. Retrying " >> $RTL_LOG_FILE
            $CONFIGPARAMGEN jx $PEER_COMM_DAT $PEER_COMM_ID 
            scp -i $PEER_COMM_ID -r $ARM_INTERFACE_IP:$DCMRESPONSE $DCMRESPONSE > /dev/null 2>&1
            rm -f $PEER_COMM_ID
            sleep 10
        done
    fi
    processJsonResponse "$DCMRESPONSE"
    clearTelemetryConfig
    generateTelemetryConfig $TELEMETRY_PROFILE_PATH $SORTED_PATTERN_CONF_FILE
    scheduleCron
    if [ $triggerType -eq 1 ]; then
        ## Telemetry must be invoked only via cron and not during boot-up
		pidCleanup
        exit 0
    fi
fi

if [ "x$DCA_MULTI_CORE_SUPPORTED" = "xyes" ]; then
    dropbearRecovery
    mkdir -p $LOG_PATH
    TMP_SCP_PATH="/tmp/scp_logs"
    mkdir -p $TMP_SCP_PATH
    $CONFIGPARAMGEN jx $PEER_COMM_DAT $PEER_COMM_ID
    scp -i $PEER_COMM_ID -r $ARM_INTERFACE_IP:$LOG_PATH/* $TMP_SCP_PATH/ > /dev/null 2>&1
    scp -i $PEER_COMM_ID -r $ARM_INTERFACE_IP:$LOG_SYNC_PATH/$SelfHealBootUpLogFile  $ARM_INTERFACE_IP:$LOG_SYNC_PATH/$PcdLogFile $TMP_SCP_PATH/ > /dev/null 2>&1
    rm -f $PEER_COMM_ID

    RPC_RES=`rpcclient $ARM_ARPING_IP "touch $SCP_COMPLETE"`
    RPC_OK=`echo $RPC_RES | grep "RPC CONNECTED"`
    if [ "$RPC_OK" == "" ]; then
	 echo_t "RPC touch failed : attemp 1"

	 RPC_RES=`rpcclient $ARM_ARPING_IP "touch $SCP_COMPLETE"`
     RPC_OK=`echo $RPC_RES | grep "RPC CONNECTED"`
	 if [ "$RPC_OK" == "" ]; then
		echo_t "RPC touch failed : attemp 2"
	 fi
    fi

    ATOM_FILE_LIST=`echo ${ATOM_FILE_LIST} | sed -e "s/{//g" -e "s/}//g" -e "s/,/ /g"`
    for file in $ATOM_FILE_LIST
    do
        if [ -f $TMP_SCP_PATH/$file ]; then
            rm -f $TMP_SCP_PATH/$file
        fi
    done

    if [ -d $TMP_SCP_PATH ]; then
        cp -r $TMP_SCP_PATH/* $LOG_PATH/
        rm -rf $TMP_SCP_PATH
    fi

    sleep 2
fi

#Clear the final result file
rm -f $OUTPUT_FILE
rm -f $TELEMETRY_JSON_RESPONSE


if [ -f $EXEC_COUNTER_FILE ]; then
    dcaNexecCounter=`cat $EXEC_COUNTER_FILE`
    dcaNexecCounter=`expr $dcaNexecCounter + 1`
else
    dcaNexecCounter=0;
fi

## Generate output file with pattern to match count values
if [ ! -f $SORTED_PATTERN_CONF_FILE ]; then
    echo "WARNING !!! Unable to locate telemetry config file $SORTED_PATTERN_CONF_FILE. Exiting !!!" >> $RTL_LOG_FILE
else
    echo_t "Using telemetry pattern stored in : $SORTED_PATTERN_CONF_FILE.!!!" >> $RTL_LOG_FILE
    while read line
    do
        pattern=`echo "$line" | awk -F '<#=#>' '{print $1}'`
        filename=`echo "$line" | awk -F '<#=#>' '{print $2}'`
        skipInterval=`echo "$line" | awk -F '<#=#>' '{print $3}'`
        
        if [ ! -z "$pattern" ] && [ ! -z "$filename" ]; then
            ## updateCount "$pattern" "$filename"
            if [ -f $LOG_PATH/$filename ]; then
                updateCount
            fi
        fi
    done < $SORTED_PATTERN_CONF_FILE
fi

## Form the message in JSON format
if [ -f $OUTPUT_FILE ]; then    
    outputJson="{\"searchResult\":["
    singleEntry=true
    while read line
    do
         searchPattern=`echo "$line" | awk -F '<#=#>' '{print $1}'`
         filename=`echo "$line" | awk -F '<#=#>' '{print $2}'`
         header=`grep -F "$searchPattern<#=#>$filename" $MAP_PATTERN_CONF_FILE | head -n 1 | awk -F '<#=#>' '{print $1}'`
         start_string=`echo "$line" | cut -c 1-4`
         #If the pattern starts with RDK- set header with pattern
         if [ "$start_string" == "RDK-" ]; then
            header=$searchPattern
         fi
         searchCount=`echo "$line" | awk -F '<#=#>' '{print $NF}'`
         tempString=""
         if [ ! -z "$searchCount" ]; then
             if $singleEntry ; then
                 tempString="{\"$header\":\"$searchCount\"}"
                 singleEntry=false
             else
                 tempString=",{\"$header\":\"$searchCount\"}"
             fi
             outputJson="$outputJson$tempString"
         fi
    done < $OUTPUT_FILE
       
    # Get the snmp and performance values when enabled 
    # Need to check only when SNMP is enabled in future
    if [ "$snmpCheck" == "true" ] ; then
      while read line
      do
        pattern=`echo "$line" | awk -F '<#=#>' '{print $1}'`
        filename=`echo "$line" | awk -F '<#=#>' '{print $2}'`
        if [ $filename == "snmp" ] || [ $filename == "SNMP" ]; then
            retvalue=$(getSNMPUpdates $pattern)
            header=`grep "$pattern<#=#>$filename" $MAP_PATTERN_CONF_FILE | head -n 1 | awk -F '<#=#>' '{print $1}'`
            if $singleEntry ; then
               tuneData="{\"$header\":\"$retvalue\"}"
               outputJson="$outputJson$tuneData"
               singleEntry=false
            else
               tuneData=",{\"$header\":\"$retvalue\"}"
               outputJson="$outputJson$tuneData" 
            fi                
        fi
            
        if [ $filename == "top_log.txt" ]; then            
            header=`grep "$pattern<#=#>$filename" $MAP_PATTERN_CONF_FILE | head -n 1 | awk -F '<#=#>' '{print $1}'`
            if [ "$header" == "Load_Average" ]; then                    
                load_average=`getLoadAverage`
                if $singleEntry ; then
                    outputJson="$outputJson$load_average"
                    singleEntry=false
                else
                    outputJson="$outputJson,$load_average"
                fi              
            else
                retvalue=$(getPerformanceValue $pattern)
                if [ -n "$retvalue" ]; then
                    if $singleEntry ; then
                        tuneData="$retvalue"
                        outputJson="$outputJson$tuneData"
                        singleEntry=false
                    else
                        tuneData=",$retvalue"
                        outputJson="$outputJson$tuneData" 
                    fi
                fi
           fi
       fi
       done < $SORTED_PATTERN_CONF_FILE
     fi

       ## This interface is not accessible from ATOM, replace value from ARM
       estbMac="ErouterMacAddress"
       firmwareVersion=$(getFWVersion)
       firmwareVersion=$(echo $firmwareVersion | sed -e "s/imagename://g")
       partnerId=$(getPartnerId)
       erouterIpv4=$(getErouterIpv4)
       erouterIpv6=$(getErouterIpv6)

       cur_time=`date "+%Y-%m-%d %H:%M:%S"`
     
       if $singleEntry ; then
            outputJson="$outputJson,{\"Profile\":\"RDKB\"},{\"mac\":\"$estbMac\"},{\"erouterIpv4\":\"$erouterIpv4\"},{\"erouterIpv6\":\"$erouterIpv6\"},{\"PartnerId\":\"$partnerId\"},{\"Version\":\"$firmwareVersion\"},{\"Time\":\"$cur_time\"}]}"
            singleEntry=false
       else
            outputJson="$outputJson,{\"Profile\":\"RDKB\"},{\"mac\":\"$estbMac\"},{\"erouterIpv4\":\"$erouterIpv4\"},{\"erouterIpv6\":\"$erouterIpv6\"},{\"PartnerId\":\"$partnerId\"},{\"Version\":\"$firmwareVersion\"},{\"Time\":\"$cur_time\"}]}"
       fi
       echo "$outputJson" > $TELEMETRY_JSON_RESPONSE
       sleep 2

       if [ "x$DCA_MULTI_CORE_SUPPORTED" = "xyes" ]; then
           echo "Notify ARM to pick the updated JSON message in $TELEMETRY_JSON_RESPONSE and upload to splunk" >> $RTL_LOG_FILE
           # Trigger inotify event on ARM to upload message to splunk
           $CONFIGPARAMGEN jx $PEER_COMM_DAT $PEER_COMM_ID
           if [ $triggerType -eq 2 ]; then
               ssh -i $PEER_COMM_ID root@$ARM_INTERFACE_IP "/bin/echo 'notifyFlushLogs' > $TELEMETRY_INOTIFY_EVENT"  > /dev/null 2>&1
               echo_t "notify ARM for dca execution completion" >> $RTL_LOG_FILE
           else
               ssh -i $PEER_COMM_ID root@$ARM_INTERFACE_IP "/bin/echo 'splunkUpload' > $TELEMETRY_INOTIFY_EVENT" > /dev/null 2>&1
           fi
           rm -f $PEER_COMM_ID
       else
           if [ $triggerType -eq 2 ]; then
               touch $TELEMETRY_EXEC_COMPLETE
           fi
           sh /lib/rdk/dcaSplunkUpload.sh &
       fi
fi

if [ -f $RTL_DELTA_LOG_FILE ]; then
    rm -f $RTL_DELTA_LOG_FILE
fi

if [ -f $TEMP_PATTERN_CONF_FILE ]; then
    rm -f $TEMP_PATTERN_CONF_FILE
fi

if [ $triggerType -eq 2 ]; then
   echo_t "forced DCA execution before log upload/reboot. Clearing all markers !!!" >> $RTL_LOG_FILE
   # Forced execution before flusing of logs, so clear the markers
   if [ -d $TELEMETRY_PATH_TEMP ]; then
       rm -rf $TELEMETRY_PATH_TEMP
   fi
fi

echo "$dcaNexecCounter" > $EXEC_COUNTER_FILE
# PID file cleanup
pidCleanup
