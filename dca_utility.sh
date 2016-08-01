#!/bin/sh

. /etc/include.properties
. /etc/device.properties

if [ -f /lib/rdk/utils.sh  ]; then
   . /lib/rdk/utils.sh
fi


DCMRESPONSE="$PERSISTENT_PATH/DCMresponse.txt"
DCM_SETTINGS_CONF="/tmp/DCMSettings.conf"

TELEMETRY_PATH="$PERSISTENT_PATH/.telemetry"
TELEMETRY_PATH_TEMP="$TELEMETRY_PATH/tmp"
TELEMETRY_PROFILE_PATH="$PERSISTENT_PATH/.DCMSettings.conf"

RTL_LOG_FILE="$LOG_PATH/dcmscript.log"
RTL_DELTA_LOG_FILE="$RAMDISK_PATH/.rtl_temp.log"
PATTERN_CONF_FILE="$TELEMETRY_PATH/dca.conf"
MAP_PATTERN_CONF_FILE="$TELEMETRY_PATH/dcafile.conf"
TEMP_PATTERN_CONF_FILE="$TELEMETRY_PATH/temp_dcafile.conf"

# Persist this files for telemetry operation
# Regenerate this only when there is a change identified from XCONF update
SORTED_PATTERN_CONF_FILE="$TELEMETRY_PATH/dca_temp_file.conf"

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

if [ "x$DCA_MULTI_CORE_SUPPORTED" = "xyes" ]; then
    CRON_SPOOL=/tmp/cron
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
    fi
fi

if [ "$LIGHTSLEEP_ENABLE" == "true" ] && [ -f /tmp/.standby ]; then
    if [ ! -f /etc/os-release ];then pidCleanup; fi    
    exit 0
fi

mkdir -p $LOG_PATH
touch $RTL_LOG_FILE

if [ ! -f /tmp/.dca_bootup ]; then
   touch /tmp/.dca_bootup
   rm -rf $TELEMETRY_PATH
fi


PrevFileName=''

echo "Telemetry Profile File Being Used : $TELEMETRY_PROFILE_PATH" >> $RTL_LOG_FILE
	
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
    echo "Telemetry Folder exists" >> $RTL_LOG_FILE
    cp $TELEMETRY_PATH/rtl_* $TELEMETRY_PATH_TEMP/
    echo "Copied Files to temp directory" >> $RTL_LOG_FILE
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
   echo "Usage : `basename $0` <0/1> 0 - Reinitialize Map 1 - Telemetry search " >> $RTL_LOG_FILE
   if [ ! -f /etc/os-release ];then pidCleanup; fi
   exit 0
fi

reconfigure=$1

cd $LOG_PATH
timestamp=`date +%Y-%b-%d_%H-%M-%S`

isNum()
{
    Number=$1
    if [ $Number -ne 0 -o $Number -eq 0 2>/dev/null ];then
        echo 0
    else
        echo 1
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
     performance_value=`$PERFORMANCE_BINARY $process_name`
     echo $performance_value
}

# Function to get performance values 
getLoadAverage() {
     load_average=''
     load_average=`$LOAD_AVG_BINARY`
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
    timestamp=`date +%Y-%b-%d_%H-%M-%S`
    # Need not create the dela file is the previous file in MAP is the same 
    if [ "$filename" != "$PrevFileName" ]; then    
       PrevFileName=$filename
       rm -f $RTL_DELTA_LOG_FILE
       nice $TEMPFILE_CREATER_BINARY $filename
    fi
    header=`grep -F "$pattern<#=#>$filename" $MAP_PATTERN_CONF_FILE | head -n 1 | awk -F '<#=#>' '{print $1}'`
    case "$header" in
        *split*)  
	 final_count=`$IPVIDEO_BINARY $RTL_DELTA_LOG_FILE "$pattern"` ;;
	*) 
	 final_count=`$TEMPFILE_PARSE_BINARY $RTL_DELTA_LOG_FILE "$pattern" | awk -F '=' '{print $NF}'` ;;
    esac
    # Update count and patterns in a single file 
    if [ "$final_count" != "0" ]; then
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
			echo "$cron nice -n 20 sh $RDK_PATH/dca_utility.sh 0" >> $tempfile
		fi
		while read line
		do
			retval=`echo "$line" | grep 'dca_utility.sh'`
			if [ -n "$retval" ]; then
				echo "$cron nice -n 20 sh $RDK_PATH/dca_utility.sh 0" >> $tempfile
			else
				echo "$line" >> $tempfile
			fi
		done < $current_cron_file
	else
		# If no cron job exists, create one, with the value from DCMSettings.conf file
		echo "$cron nice -n 20 sh $RDK_PATH/dca_utility.sh 0" >> $tempfile
	fi
	# Set new cron job from the file
	crontab $tempfile -c $CRON_SPOOL
	rm -rf $current_cron_file # Delete temp file
	rm -rf $tempfile          # Delete temp file
    else
	echo " `date` Failed to read \"schedule\" cronjob value from DCMSettings.conf." >> $RTL_LOG_FILE
    fi
}
   
clearTelemetryConfig()
{
    if [ -f $RTL_DELTA_LOG_FILE ]; then
        echo "$timestamp: dca: Deleting : $RTL_DELTA_LOG_FILE" >> $RTL_LOG_FILE
        rm -f $RTL_DELTA_LOG_FILE
    fi

    if [ -f $PATTERN_CONF_FILE ]; then
        echo "$timestamp: dca: PATTERN_CONF_FILE : $PATTERN_CONF_FILE" >> $RTL_LOG_FILE
        rm -f $PATTERN_CONF_FILE
    fi

    if [ -f $MAP_PATTERN_CONF_FILE ]; then
        echo "$timestamp: dca: MAP_PATTERN_CONF_FILE : $MAP_PATTERN_CONF_FILE" >> $RTL_LOG_FILE
        rm -f $MAP_PATTERN_CONF_FILE
    fi

    if [ -f $TEMP_PATTERN_CONF_FILE ]; then
        echo "$timestamp: dca: TEMP_PATTERN_CONF_FILE : $TEMP_PATTERN_CONF_FILE" >> $RTL_LOG_FILE
        rm -f $TEMP_PATTERN_CONF_FILE
    fi

    if [ -f $SORTED_PATTERN_CONF_FILE ]; then
        echo "$timestamp: dca: SORTED_PATTERN_CONF_FILE : $SORTED_PATTERN_CONF_FILE" >> $RTL_LOG_FILE
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
              type=`echo "$line" | awk -F '"type" :' '{print $NF}' | awk -F '",' '{print $1}' | sed -e 's/^[ ]//' | sed 's/^"//'`
              pollingFrequency=`echo "$line" | awk -F '"pollingFrequency" :' '{print $NF}' | sed -e 's/^[ ]//' | sed 's/^"//' | sed 's/"}//'`        
              if [ -n "$header" ] && [ -n "$content" ] && [ -n "$type" ]; then
                  echo "$header<#=#>$content<#=#>$type" >> $MAP_PATTERN_CONF_FILE
              fi
           else
              header=`echo "$line" | awk -F '"header" :' '{print $NF}' | awk -F '",' '{print $1}' | sed -e 's/^[ ]//' | sed 's/^"//'`
              content=`echo "$line" | awk -F '"content" :' '{print $NF}' | awk -F '",' '{print $1}' | sed -e 's/^[ ]//' | sed 's/^"//'`
              type=`echo "$line" | awk -F '"type" :' '{print $NF}' | sed -e 's/^[ ]//' | sed 's/^"//' | sed 's/"}//'`
              if [ -n "$header" ] && [ -n "$content" ] && [ -n "$type" ]; then
                  echo "$header<#=#>$content<#=#>$type" >> $MAP_PATTERN_CONF_FILE
              fi
           fi 
        fi
    done < $TEMP_PATTERN_CONF_FILE

    #Create conf file from map file
    while read line
    do
        content=`echo "$line" | awk -F '<#=#>' '{print $2}'`
        type=`echo "$line" | awk -F '<#=#>' '{print $3}'`
        echo "$content<#=#>$type" >> $PATTERN_CONF_FILE
    done < $MAP_PATTERN_CONF_FILE

    # Sort the config file based on file names to minimise the duplicate delta file generation
    if [ -f $PATTERN_CONF_FILE ]; then
        if [ -f $output_file ]; then
            rm -f $output_file
        fi
        awk -F '<#=#>' '{print $NF,$0}' $PATTERN_CONF_FILE | sort -n | cut -d ' ' -f 2- > $output_file 
    fi

}

# Regenerate config only during boot-up and when there is an update
if [ ! -f $SORTED_PATTERN_CONF_FILE ] || [ $reconfigure -eq 1 ] ; then
# Start crond daemon for yocto builds
    pidof crond
    if [ $? -ne 0 ]; then
        mkdir -p $CRON_SPOOL
        touch $CRON_SPOOL/root
        crond -c $CRON_SPOOL -l 9
    fi

    processJsonResponse "$DCMRESPONSE"
    clearTelemetryConfig
    generateTelemetryConfig $TELEMETRY_PROFILE_PATH $SORTED_PATTERN_CONF_FILE
    scheduleCron
fi


#Clear the final result file
rm -f $OUTPUT_FILE
rm -f $TELEMETRY_JSON_RESPONSE

if [ "x$DCA_MULTI_CORE_SUPPORTED" = "xyes" ]; then
    # Need to move to rsync once rsync is enabled in master
    mkdir -p $LOG_PATH
    scp -r $ARM_INTERFACE_IP:$LOG_PATH/* $LOG_PATH/
fi

## Generate output file with pattern to match count values
if [ ! -f $SORTED_PATTERN_CONF_FILE ]; then
    echo "WARNING !!! Unable to locate telemetry config file $SORTED_PATTERN_CONF_FILE. Exiting !!!" >> $RTL_LOG_FILE
else
    while read line
    do
        pattern=`echo "$line" | awk -F '<#=#>' '{print $1}'`
        filename=`echo "$line" | awk -F '<#=#>' '{print $2}'`
        
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
       cur_time=`date "+%Y-%m-%d %H:%M:%S"`
     
       if $singleEntry ; then
            outputJson="$outputJson{\"mac\":\"$estbMac\"},{\"Version\":\"$firmwareVersion\"},{\"Time\":\"$cur_time\"}]}"
            singleEntry=false
       else
            outputJson="$outputJson,{\"mac\":\"$estbMac\"},{\"Version\":\"$firmwareVersion\"},{\"Time\":\"$cur_time\"}]}"
       fi
       echo "$outputJson" > $TELEMETRY_JSON_RESPONSE
       sleep 2

       if [ "x$DCA_MULTI_CORE_SUPPORTED" = "xyes" ]; then
           echo "Notify ARM to pick the updated JSON message in $TELEMETRY_JSON_RESPONSE and upload to splunk"
           echo "Notify ARM to pick the updated JSON message in $TELEMETRY_JSON_RESPONSE and upload to splunk" >> $RTL_LOG_FILE
           # Trigger inotify event on ARM to upload message to splunk
           ssh root@$ARM_INTERFACE_IP "/bin/echo 'splunkUpload' > $TELEMETRY_INOTIFY_EVENT"
       else
           sh /lib/rdk/dcaSplunkUpload.sh &
       fi
else
    echo "$timestamp: dca: Configuration File Not Found" >> $RTL_LOG_FILE
fi

if [ -f $RTL_DELTA_LOG_FILE ]; then
    rm -f $RTL_DELTA_LOG_FILE
fi

if [ -f $TEMP_PATTERN_CONF_FILE ]; then
    rm -f $TEMP_PATTERN_CONF_FILE
fi

# PID file cleanup
if [ ! -f /etc/os-release ];then pidCleanup; fi
