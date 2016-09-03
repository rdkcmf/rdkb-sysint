#!/bin/sh

LOG_FOLDER="/rdklogs/logs/"
ATOMCONSOLELOGFILE="$LOG_FOLDER/AtomConsolelog.txt.0"
exec 3>&1 4>&2 >>$ATOMCONSOLELOGFILE 2>&1

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

    echo "USED_MEM_ATOM : Used mem is $usedMemSys at timestamp $timestamp"
    echo "FREE_MEM_ATOM :Free mem is $freeMemSys at timestamp $timestamp"

    LOAD_AVG=`uptime | awk -F'[a-z]:' '{ print $2}' | sed 's/^ *//g' | sed 's/,//g' | sed 's/ /:/g'`
	echo " RDKB_LOAD_AVERAGE_ATOM : Load Average is $LOAD_AVG at timestamp $timestamp"
    echo "LOAD_AVERAGE_ATOM :$LOAD_AVG"
    
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
	echo "USED_CPU_ATOM :$Curr_CPULoad"
	count=$((count + 1))

        echo "Count = $count"
        CPU_INFO=`mpstat | tail -1` 
	echo "RDKB_CPUINFO_ATOM : Cpu Info is $CPU_INFO at timestamp $timestamp"

	if [ "$count" -eq "$max_count" ]
	then
		echo "RDKB_PROC_MEM_LOG_ATOM : Process Memory log at $timestamp is"
		echo ""
		top -m -b n 1

		echo "================================================================================"
		echo ""
		echo "RDKB_DISK_USAGE_ATOM : Systems Disk Space Usage log at $timestamp is"
		echo ""
		disk_usage="df"
		eval $disk_usage
		count=0
	
	else
		echo "RDKB_PROC_MEM_LOG_ATOM : Process Memory log at $timestamp is"
		echo ""
		top -m -b n 1 | head -n 14
	fi


if [ -f $COUNTINFO ]
then
	echo $count > $COUNTINFO
else
	touch $COUNTINFO
	echo $count > $COUNTINFO
fi

