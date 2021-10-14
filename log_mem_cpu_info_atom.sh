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

T2_MSG_CLIENT=/usr/bin/telemetry2_0_client

t2ValNotify() {
    if [ -f $T2_MSG_CLIENT ]; then
        marker=$1
        shift
        $T2_MSG_CLIENT "$marker" "$*"
    fi
}

uptime=$(cut -d. -f1 /proc/uptime)
echo "before running log_mem_cpu_info_atom.sh.sh printing top output" >> /rdklogs/logs/CPUInfoPeer.txt.0
top -n1 -b >> /rdklogs/logs/CPUInfoPeer.txt.0
if [ $uptime -gt 1800 ] && [ "$(pidof CcspWifiSsp)" != "" ] && [ "$(pidof apup)" == "" ] && [ "$(pidof fastdown)" == "" ] && [ "$(pidof apdown)" == "" ]  && [ "$(pidof aphealth.sh)" == "" ] && [ "$(pidof radiohealth.sh)" == "" ] && [ "$(pidof aphealth_log.sh)" == "" ] && [ "$(pidof bandsteering.sh)" == "" ] && [ "$(pidof l2shealth_log.sh)" == "" ] && [ "$(pidof l2shealth.sh)" == "" ] && [ "$(pidof dailystats_log.sh)" == "" ] && [ "$(pidof dailystats.sh)" == "" ]; then
	if [ -e /rdklogger/log_capture_path_atom.sh ]
	then
		source /rdklogger/log_capture_path_atom.sh 
	else
		echo_t()
		{
			echo $1
		}
	fi

TMPFS_THRESHOLD=85

	COUNTINFO="/tmp/cpuinfocount.txt"

	getDate()
	{
		dandt_now=`date +'%Y:%m:%d:%H:%M:%S'`
		echo "$dandt_now"
	}

	getDateTime()
	{
		dandtwithns_now=`date +'%Y-%m-%d:%H:%M:%S:%6N'`
		echo "$dandtwithns_now"
	}

	getstat() {
	    grep 'cpu ' /proc/stat | sed -e 's/  */x/g' -e 's/^cpux//'
	}

	extract() {
	    echo $1 | cut -d 'x' -f $2
	}

	change() {
	    local e=$(extract $ENDSTAT $1)
	    local b=$(extract $STARTSTAT $1)
	    local diff=$(( $e - $b ))
	    echo $diff
	}

	max_count=12
	DELAY=30
	if [ -f $COUNTINFO ]
	then
		count=`cat $COUNTINFO`
	else
		count=0
	fi

	timestamp=`getDate`

		totalMemSys=`free | awk 'FNR == 2 {print $2}'`
		usedMemSys=`free | awk 'FNR == 2 {print $3}'`
		freeMemSys=`free | awk 'FNR == 2 {print $4}'`

		echo "RDKB_SYS_MEM_INFO_ATOM : Total memory in system is $totalMemSys at timestamp $timestamp"
		echo "RDKB_SYS_MEM_INFO_ATOM : Used memory in system is $usedMemSys at timestamp $timestamp"
		echo "RDKB_SYS_MEM_INFO_ATOM : Free memory in system is $freeMemSys at timestamp $timestamp"

	    echo "RDKB_USED_MEM_ATOM : Used mem is $usedMemSys at timestamp $timestamp"
	    echo "USED_MEM_ATOM:$usedMemSys"
	    echo "FREE_MEM_ATOM :Free mem is $freeMemSys at timestamp $timestamp"
            t2ValNotify "USED_MEM_ATOM_split" "$usedMemSys"

	    LOAD_AVG=`uptime | awk -F'[a-z]:' '{ print $2}' | sed 's/^ *//g' | sed 's/,//g' | sed 's/ /:/g'`
	    echo " RDKB_LOAD_AVERAGE_ATOM : Load Average is $LOAD_AVG at timestamp $timestamp"
	    LOAD_AVG_15=`echo $LOAD_AVG | cut -f3 -d:`
	    echo_t "LOAD_AVERAGE_ATOM:$LOAD_AVG_15"
	    t2ValNotify "LOAD_AVG_ATOM_split" "$LOAD_AVG_15"

	    #Record the start statistics

		STARTSTAT=$(getstat)

		sleep $DELAY

	    #Record the end statistics
		ENDSTAT=$(getstat)

		USR=$(change 1)
		SYS=$(change 3)
		IDLE=$(change 4)
		IOW=$(change 5)


		ACTIVE=$(( $USR + $SYS + $IOW ))

		TOTAL=$(($ACTIVE + $IDLE))

		Curr_CPULoad=$(( $ACTIVE * 100 / $TOTAL ))
		timestamp=`getDate`
		echo "RDKB_CPU_USAGE_ATOM : CPU usage is $Curr_CPULoad at timestamp $timestamp"
		echo_t "USED_CPU_ATOM:$Curr_CPULoad"
                t2ValNotify "USED_CPU_ATOM_split" "$Curr_CPULoad"

		count=$((count + 1))

		echo_t "Count = $count"
		CPU_INFO=`mpstat | tail -1` 
		echo "RDKB_CPUINFO_ATOM : Cpu Info is $CPU_INFO at timestamp $timestamp"

                TMPFS_CUR_USAGE=0
                TMPFS_CUR_USAGE=`df /tmp | tail -1 | awk '{print $(NF-1)}' | cut -d"%" -f1`

		if [ "$count" -eq "$max_count" ]
		then
			echo "RDKB_PROC_MEM_LOG_ATOM : Process Memory log at $timestamp is" >> /rdklogs/logs/CPUInfoPeer.txt.0
			echo_t "" >> /rdklogs/logs/CPUInfoPeer.txt.0
			top -m -b n 1 >> /rdklogs/logs/CPUInfoPeer.txt.0

			echo_t "================================================================================" >> /rdklogs/logs/CPUInfoPeer.txt.0
			echo_t ""
			echo "RDKB_DISK_USAGE_ATOM : Systems Disk Space Usage log at $timestamp is"
			echo_t ""
			disk_usage="df"
			eval $disk_usage
                	count=0
                        echo_t "TMPFS_USAGE_ATOM_PERIODIC:$TMPFS_CUR_USAGE"
	                t2ValNotify "TMPFS_USAGE_ATOM_PERIODIC" "$TMPFS_CUR_USAGE"	
                        if [ $TMPFS_CUR_USAGE -ge $TMPFS_THRESHOLD ]
                        then
                            echo_t "TMPFS_USAGE_ATOM:$TMPFS_CUR_USAGE"
                            t2ValNotify "TMPFS_USAGE_ATOM" "$TMPFS_CUR_USAGE"
                        fi
		else
			echo "RDKB_PROC_MEM_LOG_ATOM : Process Memory log at $timestamp is" >> /rdklogs/logs/CPUInfoPeer.txt.0
			echo_t "" >> /rdklogs/logs/CPUInfoPeer.txt.0
			top -m -b n 1 | head -n 14 >> /rdklogs/logs/CPUInfoPeer.txt.0
                        if [ $TMPFS_CUR_USAGE -ge $TMPFS_THRESHOLD ]
                        then
                            disk_usage="df"
                            eval $disk_usage
                            echo_t "TMPFS_USAGE_ATOM:$TMPFS_CUR_USAGE"
                            t2ValNotify "TMPFS_USAGE_ATOM" "$TMPFS_CUR_USAGE"
                        fi
		fi

	if [ -f $COUNTINFO ]
	then
		echo $count > $COUNTINFO
	else
		touch $COUNTINFO
		echo $count > $COUNTINFO
	fi

	# do saplogging only if any type of swap is enabled
	swap_devices=`cat /proc/swaps | wc -l`
	if [ $swap_devices -gt 1 ]; then
	    # swap usage information
	    # vmInfoHeader: swpd,free,buff,cache,si,so
	    # vmInfoValues: <int>,<int>,<int>,<int>,<int>,<int>
	    echo "VM STATS SINCE BOOT ATOM"
	    swaped=`free | awk 'FNR == 4 {print $3}'`
	    cache=`cat /proc/meminfo | awk 'FNR == 4 {print $2}'`
	    buff=`cat /proc/meminfo | awk 'FNR == 3 {print $2}'`
        swaped_in=`grep pswpin /proc/vmstat | cut -d ' ' -f2`
        swaped_out=`grep pswpout /proc/vmstat | cut -d ' ' -f2`
	    # conversion to kb assumes 4kb page, which is quite standard
	    swaped_in_kb=$(($swaped_in * 4))
	    swaped_out_kb=$(($swaped_out * 4))
	    echo vmInfoHeader: swpd,free,buff,cache,si,so
	    echo vmInfoValues: $swaped,$freeMemSys,$buff,$cache,$swaped_in,$swaped_out
	    # end of swap usage information block
        fi
        nvram_fsck="/rdklogger/nvram_rw_restore.sh"
	nvram_ro_fs=`mount | grep "nvram " | grep dev | grep "[ (]ro[ ,]"`
	if [ "$nvram_ro_fs" != "" ]; then
		echo "[RDKB_SELFHEAL] : NVRAM ON ATOM IS READ-ONLY"
                if [ -f $nvram_fsck ] && [ ! -e /tmp/atom_ro ]; then
                    source $nvram_fsck
                fi
	fi


        echo "after running log_mem_cpu_info_atom..sh printing top output" >> /rdklogs/logs/CPUInfoPeer.txt.0 
	top -n1 -b >> /rdklogs/logs/CPUInfoPeer.txt.0
else
	echo "skipping log_mem_cpu_info_atom.sh run" >> /rdklogs/logs/AtomConsolelog.txt.0
fi

