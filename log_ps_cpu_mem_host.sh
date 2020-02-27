#!/bin/sh
##################################################################################
# If not stated otherwise in this file or this component's Licenses.txt file the
# following copyright and licenses apply:
#
#  Copyright 2018 RDK Management
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
################################################################################
. /etc/include.properties
source /etc/log_timestamp.sh

ps_names="CcspCMAgentSsp CcspPandMSsp CcspHomeSecurity CcspMoCA CcspTandDSsp CcspXdnsSsp CcspEthAgent CcspLMLite PsmSsp notify_comp"
page_size=4
cpu=0
mem=0
LOG_FILE="$LOG_PATH/CPUInfo.txt.0"

getCPU()
{
    prev_cpu_time=`awk '/^cpu / {t=0; for(i=2;i<=NF;i++) t+=$i} END {print t}' </proc/stat`
    prev_proc_time=`awk '{p=0; for(i=14;i<=17;i++) p+=$i} END {print p}' </proc/$1/stat`
    sleep 1
    cur_cpu_time=`awk '/^cpu / {t=0; for(i=2;i<=NF;i++) t+=$i} END {print t}' </proc/stat`
    cur_proc_time=`awk '{p=0; for(i=14;i<=17;i++) p+=$i} END {print p}' </proc/$1/stat`
    total_cpu_diff=$(( $cur_cpu_time - $prev_cpu_time ))
    total_proc_diff=$(( $cur_proc_time - $prev_proc_time ))
    cpu=$(( $total_proc_diff*100 / $total_cpu_diff ))
}

getMem()
{
    total_rss=0
    
    for pid in $1
    do
        rss=$(cat /proc/$pid/stat | cut -d ' ' -f 24)
        let total_rss+=rss
    done
    
    res=$(expr $total_rss * $page_size)
    mem=$res
    
    if [ $res -ge 1024 ];
    then
        mem=$(expr $res / 1024)
    fi
    
    if [ $mem -ge 1024 ];
    then
        mem="${mem}m"
    else
        mem="${mem}k"
    fi
}

for ps_name in $ps_names
do
    pid=$(pidof $ps_name)
    cpu=0
    mem=0
    getCPU $pid
    getMem $pid
    
    cpu_mem_info="${cpu_mem_info}${ps_name}_cpu:$cpu\n${ps_name}_mem:$mem\n"
done
echo_t "CPU and MEM INFO" >> $LOG_FILE
echo -e "$cpu_mem_info" >> $LOG_FILE
