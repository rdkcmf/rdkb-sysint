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
# Scripts having common utility functions

if [ -f /etc/utopia/service.d/log_env_var.sh ];then
	source /etc/utopia/service.d/log_env_var.sh
fi

if [ -f /etc/utopia/service.d/log_capture_path.sh ];then
    source /etc/utopia/service.d/log_capture_path.sh
fi

source /etc/waninfo.sh

if [ "$BOX_TYPE" = "XF3" ]; then
CMINTERFACE="erouter0"
else
CMINTERFACE="wan0"
fi

WANINTERFACE=$(getWanInterfaceName)
CRONTAB_DIR="/var/spool/cron/crontabs/"
CRONFILE_BK="/tmp/cron_tab$$$$.txt"

#checkProcess()
#{
#  ps -ef | grep $1 | grep -v grep
#}

Timestamp()
{
	    date +"%Y-%m-%d %T"
}

# Set the name of the log file using SHA1
#setLogFile()
#{
#    fileName=`basename $6`
#    echo $1"_mac"$2"_dat"$3"_box"$4"_mod"$5"_"$fileName
#}

# Get the MAC address of the machine
getMacAddressOnly()
{
     if [ "$BOX_TYPE" = "HUB4" ] || [ "$BOX_TYPE" = "SR300" ] || [ "$BOX_TYPE" = "SE501" ] || [ "$BOX_TYPE" = "SR213" ]; then
         #FEATURE_RDKB_WAN_MANAGER
         mac=`cat /sys/class/net/$WANINTERFACE/address | tr '[a-f]' '[A-F]' `
         if [ -z "$mac" ]; then
            mac=$(sysevent get eth_wan_mac | tr '[a-f]' '[A-F]')
         fi
     else	
         mac=`ifconfig $WANINTERFACE | grep HWaddr | cut -d " " -f7 | sed 's/://g'`
     fi
     echo $mac
}

# Get the SHA1 checksum
getSHA1()
{
    sha1sum $1 | cut -f1 -d" "

}

# IP address of the machine
getIPAddress()
{
    if [ "x$BOX_TYPE" = "xHUB4" ] || [ "x$BOX_TYPE" = "xSR300" ] || [ "x$BOX_TYPE" = "xSE501" ] || [ "x$BOX_TYPE" = "xSR213" ]; then
       CURRENT_WAN_IPV6_STATUS=`sysevent get ipv6_connection_state`
       if [ "xup" = "x$CURRENT_WAN_IPV6_STATUS" ] ; then
               wanIP=`ifconfig $HUB4_IPV6_INTERFACE | grep Global |  awk '/inet6/{print $3}' | cut -d '/' -f1 | head -n1`
       else
               wanIP=`ifconfig $WANINTERFACE | grep "inet addr" | grep -v inet6 | cut -f2 -d: | cut -f1 -d" "`
       fi
    else
    wanIP=`ifconfig $WANINTERFACE | grep "inet addr" | grep -v inet6 | cut -f2 -d: | cut -f1 -d" "`
    fi
    echo $wanIP
}

getCMIPAddress()
{
    if [ "$BOX_TYPE" = "XB6" ] || [ "$BOX_TYPE" = "TCCBR" ]; then
       address=`dmcli eRT getv Device.X_CISCO_COM_CableModem.IPv6Address | grep string | awk '{print $5}'`
       if [ ! "$address" ]; then
          address=`dmcli eRT getv Device.X_CISCO_COM_CableModem.IPAddress | grep string | awk '{print $5}'`
       fi
    elif [ "$BOX_TYPE" = "HUB4" ] || [ "$BOX_TYPE" = "SR300" ] || [ "$BOX_TYPE" = "SE501" ] || [ "$BOX_TYPE" = "SR213" ]; then
       CURRENT_WAN_IPV6_STATUS=`sysevent get ipv6_connection_state`
       if [ "xup" = "x$CURRENT_WAN_IPV6_STATUS" ] ; then
          address=`ifconfig $HUB4_IPV6_INTERFACE | grep inet6 | grep Global | awk '/inet6/{print $3}' | grep -v 'fdd7' | cut -d '/' -f1 | head -n1`
       else
          address=`ifconfig $WANINTERFACE | grep "inet addr" | grep -v inet6 | cut -f2 -d: | cut -f1 -d" "`
       fi
    elif [ $BOX_TYPE = "XF3" ]; then
       # in PON/DSL you cant get the CM IP address, so use eRouter IP address
       address=`ifconfig $WANINTERFACE | grep "inet addr" | grep -v inet6 | cut -f2 -d: | cut -f1 -d" "` 
    else                           
       address=`ifconfig -a $CMINTERFACE | grep inet6 | tr -s " " | grep -v Link | cut -d " " -f4 | cut -d "/" -f1`
       if [ ! "$address" ]; then
          address=`ifconfig -a $CMINTERFACE | grep inet | grep -v inet6 | tr -s " " | cut -d ":" -f2 | cut -d " " -f1`
       fi
    fi
    echo $address

}

getErouterIPAddress()
{
    if [ "$BOX_TYPE" = "XB6" ] || [ "$BOX_TYPE" = "TCCBR" ]; then
        address=`dmcli eRT getv Device.DeviceInfo.X_COMCAST-COM_WAN_IPv6 | grep string | awk '{print $5}'`
        if [ ! "$address" ]; then
            address=`dmcli eRT getv Device.DeviceInfo.X_COMCAST-COM_WAN_IP | grep string | awk '{print $5}'`
        fi
    elif [ "$BOX_TYPE" = "HUB4" ] || [ "$BOX_TYPE" = "SR300" ] || [ "$BOX_TYPE" = "SE501" ] ||  [ "$BOX_TYPE" = "SR213" ]; then
        CURRENT_WAN_IPV6_STATUS=`sysevent get ipv6_connection_state`
        if [ "xup" = "x$CURRENT_WAN_IPV6_STATUS" ] ; then
            address=`ifconfig $HUB4_IPV6_INTERFACE | grep inet6 | grep Global | awk '/inet6/{print $3}' | grep -v 'fdd7' | cut -d '/' -f1 | head -n1`
        else
            address=`ifconfig $WANINTERFACE | grep "inet addr" | grep -v inet6 | cut -f2 -d: | cut -f1 -d" "`
        fi
    elif [ $BOX_TYPE = "XF3" ]; then
       # in PON/DSL you cant get the CM IP address, so use eRouter IP address
       address=`ifconfig $WANINTERFACE | grep "inet addr" | grep -v inet6 | cut -f2 -d: | cut -f1 -d" "`
    else
       address=`ifconfig -a $WANINTERFACE | grep inet6 | tr -s " " | grep -v Link | cut -d " " -f4 | cut -d "/" -f1`
       if [ ! "$address" ]; then
          address=`ifconfig -a $WANINTERFACE | grep inet | grep -v inet6 | tr -s " " | cut -d ":" -f2 | cut -d " " -f1`
       fi
    fi
    echo $address
}

processCheck()
{
   ps -ef | grep $1 | grep -v grep > /dev/null 2>/dev/null 
   if [ $? -ne 0 ]; then
         echo "1"
   else
         echo "0"
   fi
}

getMacAddress()
{
    if [ $BOX_TYPE = "XF3" ]; then                           
        mac=`dmcli eRT getv Device.DPoE.Mac_address | grep value | awk '{print $5}'`
    elif [ "$BOX_TYPE" = "XB6" ] || [ "$BOX_TYPE" = "TCCBR" ];then
        mac=`dmcli eRT getv Device.X_CISCO_COM_CableModem.MACAddress | grep value | awk '{print $5}'`
    elif [ "$BOX_TYPE" = "HUB4" ] || [ "$BOX_TYPE" = "SR300" ] || [ "$BOX_TYPE" = "SE501" ] || [ "$BOX_TYPE" = "SR213" ]; then
        #FEATURE_RDKB_WAN_MANAGER
        mac=`cat /sys/class/net/$WANINTERFACE/address | tr '[a-f]' '[A-F]' `
        if [ -z "$mac" ]; then
            mac=$(sysevent get eth_wan_mac | tr '[a-f]' '[A-F]')
        fi
    else                                                           
        mac=`ifconfig $CMINTERFACE | grep HWaddr | cut -d " " -f11`
    fi
    echo $mac
}

## Get eSTB mac address 
getErouterMacAddress()
{
    if [ "$BOX_TYPE" = "HUB4" ] || [ "$BOX_TYPE" = "SR300" ] || [ "$BOX_TYPE" = "SE501" ] ||  [ "$BOX_TYPE" = "SR213" ]; then
        #FEATURE_RDKB_WAN_MANAGER
        erouterMac=`cat /sys/class/net/$WANINTERFACE/address | tr '[a-f]' '[A-F]' `
        if [ -z "$erouterMac" ]; then
            erouterMac=$(sysevent get eth_wan_mac | tr '[a-f]' '[A-F]')
        fi
    else	
        erouterMac=`ifconfig $WANINTERFACE | grep HWaddr | cut -d " " -f7`
    fi
    echo $erouterMac
}

rebootFunc()
{
    #sync
    #Before reboot send signal to PSM process to sync db to flash and stop execution , In XB6 systemd sends Terminate signal
    if [ "$BOX_TYPE" = "XB3" ]; then

        MAX_WAIT_ITER=6
        psm_exit_wait_iter=1
        PSM_SHUTDOWN="/tmp/.forcefull_psm_shutdown"
        echo_t "Gracefully shutting down PSM process by sending SIGTERM" >> /nvram2/logs/ArmConsolelog.txt.0
        touch $PSM_SHUTDOWN
        kill -15 `pidof PsmSsp`

        while [  $psm_exit_wait_iter -le $MAX_WAIT_ITER ] ; do
            if [ "x`pidof PsmSsp`" != "x" ];then
                echo "PSM still running, iter $psm_exit_wait_iter" >> /nvram2/logs/ArmConsolelog.txt.0
            else
                echo "PSM exited after iter $psm_exit_wait_iter. Going ahead and rebooting" >> /nvram2/logs/ArmConsolelog.txt.0
                break;
            fi
            sleep 2

            psm_exit_wait_iter=$(($psm_exit_wait_iter + 1))
        done

        sync
    fi
    reboot
}

Uptime()
{
    cut -d. -f1 /proc/uptime
}

## Get Model No of the box
getModel()
{
  if [ $BOX_TYPE = "XF3" ]; then
     modelName=$(sed -n 's/^imagename[:=]"\?\([^"]*\)"\?/\1/p' /version.txt | cut -d "_" -f 1)
  else
     modelName=`dmcli eRT getv Device.DeviceInfo.ModelName | grep value | awk '{print $5}'`
     if [ "$modelName" = "" ]
     then
            modelName=`echo $MODEL_NUM`
     fi
  fi
  echo "$modelName"
}

getFWVersion()
{
    sed -n 's/^imagename[:=]"\?\([^"]*\)"\?/\1/p' /version.txt
}

getBuildType()
{
    str=$(getFWVersion)

    echo $str | grep -q 'VBN'
    if [[ $? -eq 0 ]] ; then
        echo 'vbn'
    else
        echo $str | grep -q 'PROD'
        if [[ $? -eq 0 ]] ; then
            echo 'prod'
        else
            echo $str | grep -q 'QA'
            if [[ $? -eq 0 ]] ; then
                echo 'qa'
            else
                echo 'dev'
            fi
        fi
    fi
}

removeCron()
{
    # Remove the cron job
    crontab -l -c $CRONTAB_DIR > $CRONFILE_BK
    grep -q "$1" $CRONFILE_BK
    ret=$?
    if [ $ret -eq 0 ]; then
         sed -i "/`echo $1 | sed 's/.*\///'`/d" $CRONFILE_BK
         crontab $CRONFILE_BK -c $CRONTAB_DIR
    fi
    rm -rf $CRONFILE_BK
}

addCron()
{
    # Dump existing cron jobs to a file & add new job
    crontab -l -c $CRONTAB_DIR > $CRONFILE_BK
    echo -e "$*" >> $CRONFILE_BK
    crontab $CRONFILE_BK -c $CRONTAB_DIR
    rm -rf $CRONFILE_BK
}
