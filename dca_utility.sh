#!/bin/sh

. /etc/include.properties
. /etc/device.properties

if [ -f /fss/gw/rdklogger/utils.sh  ]; then
   . /fss/gw/rdklogger/utils.sh
fi


TELEMETRY_PATH="$PERSISTENT_PATH/.telemetry"
TELEMETRY_PATH_TEMP="$TELEMETRY_PATH/tmp"
TELEMETRY_RESEND_FILE="$PERSISTENT_PATH/.resend.txt"
TELEMETRY_PROFILE_DEFAULT_PATH="/tmp/DCMSettings.conf"
TELEMETRY_PROFILE_RESEND_PATH="$PERSISTENT_PATH/.DCMSettings.conf"

RTL_LOG_FILE="$LOG_PATH/dcmscript.log"
RTL_TEMP_LOG_FILE="$RAMDISK_PATH/.rtl_temp.log"
PATTERN_CONF_FILE="$TELEMETRY_PATH/dca.conf"
MAP_PATTERN_CONF_FILE="$TELEMETRY_PATH/dcafile.conf"
TEMP_PATTERN_CONF_FILE="$TELEMETRY_PATH/temp_dcafile.conf"
SORTED_PATTERN_CONF_FILE="$TELEMETRY_PATH/dca_temp_file.conf"
OUTPUT_FILE="$LOG_PATHdca_output.txt"
MAX_RETRY_ATTEMPTS=12
HTTP_FILENAME="$TELEMETRY_PATH/dca_httpresult.txt"
HTTP_CODE="$TELEMETRY_PATH/dca_curl_httpcode"

#Performance oriented binaries
TEMPFILE_CREATER_BINARY="/usr/bin/dcaseek"
TEMPFILE_PARSE_BINARY="/usr/bin/dcafind"
PERFORMANCE_BINARY="/usr/bin/dcaprocess"
LOAD_AVG_BINARY="/usr/bin/dcaloadave"
IPVIDEO_BINARY="/usr/bin/ipvideo"

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

#0 indicates to store the information . 1 indicates to send information onto cloud.
sendInformation=$2 

if [ "$sendInformation" -ne 1 ] ; then
   TELEMETRY_PROFILE_PATH=$TELEMETRY_PROFILE_RESEND_PATH
else
   TELEMETRY_PROFILE_PATH=$TELEMETRY_PROFILE_DEFAULT_PATH
fi
	
echo "Telemetry Profile File Being Used : $TELEMETRY_PROFILE_PATH" >> $RTL_LOG_FILE
	
#Adding support for opt override for dcm.properties file
if [ "$BUILD_TYPE" != "prod" ] && [ -f $PERSISTENT_PATH/dcm.properties ]; then
      . $PERSISTENT_PATH/dcm.properties
else
      . /etc/dcm.properties
fi

if [ -f "$TELEMETRY_PROFILE_DEFAULT_PATH" ]; then    
    DCA_UPLOAD_URL=`grep '"uploadRepository:URL":"' $TELEMETRY_PROFILE_DEFAULT_PATH | awk -F 'uploadRepository:URL":' '{print $NF}' | awk -F '",' '{print $1}' | sed 's/"//g' | sed 's/}//g'`
fi

if [ -z $DCA_UPLOAD_URL ]; then
    DCA_UPLOAD_URL="https://stbrtl.xcal.tv"
fi

PrevFileName=''

if [ ! -d "$TELEMETRY_PATH_TEMP" ]
then
    echo "Telemetry Folder does not exist . Creating now" >> $RTL_LOG_FILE
    mkdir -p "$TELEMETRY_PATH_TEMP"
else
    echo "Telemetry Folder exists" >> $RTL_LOG_FILE
    cp $TELEMETRY_PATH/rtl_* $TELEMETRY_PATH_TEMP/
     echo "Copied Files to temp directory" >> $RTL_LOG_FILE
fi

pidCleanup()
{
   # PID file cleanup
   if [ -f /tmp/.dca-utility.pid ];then
        rm -rf /tmp/.dca-utility.pid
   fi
}
 
if [ $# -ne 2 ]; then
   echo "Usage : `basename $0` <Trigger Type> sendInformation 0 or 1" >> $RTL_LOG_FILE
   echo "Trigger Type : 1 (Upon log upload request)/ 0 (Count updating to file)" >> $RTL_LOG_FILE
   echo "sendInformation : 1 (Will upload telemetry information)/ 0 (Will NOT upload telemetry information)" >> $RTL_LOG_FILE
   
   if [ ! -f /etc/os-release ];then pidCleanup; fi
   exit 0
fi

cd $LOG_PATH
timestamp=`date +%Y-%b-%d_%H-%M-%S`

triggerType=1
sleep_time=$1
if [ -z $sleep_time ];then
    sleep_time=10
fi
echo "$timestamp: dca: sleep_time = $sleep_time" >> $RTL_LOG_FILE

TotalTuneCount=0
TuneFailureCount=0

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

# Function to get Offline status 
getOfflineStatus() {
    offline_status=''
    cablecard=''
    filePath=`cat $TELEMETRY_PATH/lastlog_path`
    echo "File Path = $filePath" >> $RTL_LOG_FILE
    offline_status=`nice -20 grep 'CM  STATUS :' $filePath/ocapri_log.txt | tail -1`
    echo "Last Cable Card Status = $offline_status" >> $RTL_LOG_FILE
    operational_check=`echo $offline_status | grep -c "Operational"`
    if [ $operational_check -eq 0 ]; then
        cablecard=`echo $offline_status | awk -F ': ' '{print $NF}'`
    fi
    
    rm -f $TELEMETRY_PATH/lastlog_path
    
    if [ -n "$cablecard" ]; then
        echo "{\"Cable_Card\":\"$cablecard\"}"
    fi
}
    
updateCount()
{
    final_count=0
    timestamp=`date +%Y-%b-%d_%H-%M-%S`
    
    if [ "$filename" != "$PrevFileName" ]; then    
       PrevFileName=$filename
       #echo "$timestamp: dca: filename = $filename" >> $RTL_LOG_FILE
       nice $TEMPFILE_CREATER_BINARY $filename
    fi
	
	header=`grep -F "$pattern<#=#>$filename" $MAP_PATTERN_CONF_FILE | head -n 1 | awk -F '<#=#>' '{print $1}'`
   
	case "$header" in
	*split*)  
	 final_count=`$IPVIDEO_BINARY $RTL_TEMP_LOG_FILE "$pattern"` ;;
	*) 
	 final_count=`$TEMPFILE_PARSE_BINARY $RTL_TEMP_LOG_FILE "$pattern" | awk -F '=' '{print $NF}'` ;;
	esac
	
           
    # Update count and patterns in a single file 
    #echo $final_count
    if [ $final_count != "0" ]; then
       echo "$pattern<#=#>$filename<#=#>$final_count" >> $OUTPUT_FILE
    fi
    #echo "$pattern<#=#>$filename<#=#>$final_count" >> $OUTPUT_FILE
}     
   
#main app
if [ -f $RTL_TEMP_LOG_FILE ]; then
    echo "$timestamp: dca: Deleting : $RTL_TEMP_LOG_FILE" >> $RTL_LOG_FILE
    rm -f $RTL_TEMP_LOG_FILE
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

touch $TEMP_PATTERN_CONF_FILE

rm -f $OUTPUT_FILE


if [ -f $TELEMETRY_PROFILE_PATH ]; then
    grep -i 'TelemetryProfile' $TELEMETRY_PROFILE_PATH | sed 's/=\[/\n/g' | sed 's/},/}\n/g' | sed 's/],/\n/g'| sed -e 's/^[ ]//' > $TEMP_PATTERN_CONF_FILE
fi

#Create map file from json message file
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
         #header=`echo "$line" | cut -d ':' -f2- | awk -F '",' '{print $1}' | sed -e 's/^[ ]//' | sed 's/^"//'`
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


# Search for all patterns and file from conf file
if [ -f $PATTERN_CONF_FILE ]; then
    if [ -f $SORTED_PATTERN_CONF_FILE ]; then
        rm -f $SORTED_PATTERN_CONF_FILE
    fi
    awk -F '<#=#>' '{print $NF,$0}' $PATTERN_CONF_FILE | sort -n | cut -d ' ' -f 2- > $SORTED_PATTERN_CONF_FILE #Sort the conf file with the the filename
    # Consider the list of files and patterns mentioned in conf file
    while read line
    do
        pattern=`echo "$line" | awk -F '<#=#>' '{print $1}'`
        filename=`echo "$line" | awk -F '<#=#>' '{print $2}'`
        if [ $filename == "snmp" ] || [ $filename == "SNMP" ] || [ $filename == "top_log.txt" ]; then
            continue
        fi
        
        if [ ! -z "$pattern" ] && [ ! -z "$filename" ]; then
            updateCount
        fi
    done < $SORTED_PATTERN_CONF_FILE
    
    if [ $triggerType -eq 1 ]; then
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
         #if [ $searchCount != 0 ]; then
             if $singleEntry ; then
                 tempString="{\"$header\":\"$searchCount\"}"
                 singleEntry=false
             else
                 tempString=",{\"$header\":\"$searchCount\"}"
             fi
             outputJson="$outputJson$tempString"
         #fi
       done < $OUTPUT_FILE
       
       # Get the snmp and performance values 
       #getSNMPUpdates
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
                        #header=`grep "$pattern<#=#>$filename" $MAP_PATTERN_CONF_FILE | head -n 1 | awk -F '<#=#>' '{print $1}'`
                        if $singleEntry ; then
                           #tuneData="{\"$header\":\"$retvalue\"}"
                           tuneData="$retvalue"
                           outputJson="$outputJson$tuneData"
                           singleEntry=false
                        else
                           #tuneData=",{\"$header\":\"$retvalue\"}"
                           tuneData=",$retvalue"
                           outputJson="$outputJson$tuneData" 
                        fi
                    fi
                fi
            fi
            
       done < $SORTED_PATTERN_CONF_FILE

       estbMac=`getErouterMacAddress`
       firmwareVersion=$(getFWVersion)
       cur_time=`date "+%Y-%m-%d %H:%M:%S"`
	   
        if [ -f $TELEMETRY_PATH/lastlog_path ] && [ "$DEVICE_TYPE" != "mediaclient" ];
        then            
            echo "File $TELEMETRY_PATH/lastlog_path exists." >> $RTL_LOG_FILE 
            #offline_status=$(getOfflineStatus)
            if [ -n "$offline_status" ]; then
                if $singleEntry ; then
                  outputJson="$outputJson$offline_status"
                  singleEntry=false
                else
                  outputJson="$outputJson,$offline_status" 
                fi
            fi
            
            cntrl_id=$(getControllerId)
            if $singleEntry ; then
                outputJson="$outputJson$cntrl_id"
                singleEntry=false
            else
                outputJson="$outputJson,$cntrl_id"                 
            fi
            
            rfstatus=$(getRFStatus)
            if $singleEntry ; then
                outputJson="$outputJson$rfstatus"
                singleEntry=false
            else
                outputJson="$outputJson,$rfstatus"                 
            fi            
           rm -f $TELEMETRY_PATH/lastlog_path 
        else
            echo "File $TELEMETRY_PATH/lastlog_path  does not exist. Not sending Cable Card Informtion " >> $RTL_LOG_FILE 
        fi		
        
     
        if $singleEntry ; then
            outputJson="$outputJson{\"mac\":\"$estbMac\"},{\"Version\":\"$firmwareVersion\"},{\"Time\":\"$cur_time\"}]}"
            singleEntry=false
        else
            outputJson="$outputJson,{\"mac\":\"$estbMac\"},{\"Version\":\"$firmwareVersion\"},{\"Time\":\"$cur_time\"}]}"
        fi
        
		 if [ "$sendInformation" != 1 ] ; then
           echo $outputJson >> $TELEMETRY_RESEND_FILE
		   echo "$timestamp: dca resend : Storing data to resend" >> $RTL_LOG_FILE
		   mv $TELEMETRY_PATH_TEMP/* $TELEMETRY_PATH/
        else
           timestamp=`date +%Y-%b-%d_%H-%M-%S` 
           CURL_CMD="curl -w '%{http_code}\n' --interface $EROUTER_INTERFACE -H \"Accept: application/json\" -H \"Content-type: application/json\" -X POST -d '$outputJson' -o \"$HTTP_FILENAME\" \"$DCA_UPLOAD_URL\" --connect-timeout 30 -m 10 --insecure"
           echo "$timestamp: dca: CURL_CMD: $CURL_CMD" >> $RTL_LOG_FILE 
           echo "$timestamp: dca: sleeping $sleep_time seconds" >> $RTL_LOG_FILE 
           sleep $sleep_time
           timestamp=`date +%Y-%b-%d_%H-%M-%S`
           ret= eval $CURL_CMD > $HTTP_CODE
           http_code=$(awk -F\" '{print $1}' $HTTP_CODE)
	       echo "$timestamp: dca: HTTP RESPONSE CODE : $http_code" >> $RTL_LOG_FILE
           if [ $http_code -eq 200 ];then
              echo "$timestamp: dca: Json message successfully submitted. Moving files from $TELEMETRY_PATH_TEMP to $TELEMETRY_PATH" >> $RTL_LOG_FILE
		      mv $TELEMETRY_PATH_TEMP/* $TELEMETRY_PATH/
           else
              echo "$timestamp: dca: Json message submit failed. Removing files from $TELEMETRY_PATH_TEMP" >> $RTL_LOG_FILE
		      rm -f $TELEMETRY_PATH_TEMP/*
           fi
           rm -f $OUTPUT_FILE
		   while read resend
		   do
			  echo "$timestamp: dca resend : $resend" >> $RTL_LOG_FILE 
			  CURL_CMD="curl -w '%{http_code}\n' --interface $EROUTER_INTERFACE -H \"Accept: application/json\" -H \"Content-type: application/json\" -X POST -d '$resend' -o \"$HTTP_FILENAME\" \"$DCA_UPLOAD_URL\" --connect-timeout 30 -m 10 --insecure"
              echo "$timestamp: dca resend : CURL_CMD: $CURL_CMD" >> $RTL_LOG_FILE 
		      sleep 10
			  http_code=$(awk -F\" '{print $1}' $HTTP_CODE)
	         echo "$timestamp: dca resend : HTTP RESPONSE CODE : $http_code" >> $RTL_LOG_FILE
		   done < $TELEMETRY_RESEND_FILE
		rm -f $TELEMETRY_RESEND_FILE
        fi
		
    fi
else
    echo "$timestamp: dca: Configuration File Not Found" >> $RTL_LOG_FILE
fi

if [ -f $RTL_TEMP_LOG_FILE ]; then
    rm -f $RTL_TEMP_LOG_FILE
fi

if [ -f $TEMP_PATTERN_CONF_FILE ]; then
    rm -f $TEMP_PATTERN_CONF_FILE
fi

# PID file cleanup
if [ ! -f /etc/os-release ];then pidCleanup; fi
