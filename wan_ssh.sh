#!/bin/sh
####################################################################################
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
##################################################################################
source /etc/waninfo.sh

WAN_IF=$(getWanInterfaceName)
PORT=49971
loop=1
WAN_IP4=""
WAN_IP6=""

#RDKB-16251
if [ -f /etc/mount-utils/getConfigFile.sh ];then
	. /etc/mount-utils/getConfigFile.sh
fi

get_wan_ips()
{
	while [ $loop -eq 1 ]
	do
		WAN_IF=$(getWanInterfaceName)
		#echo "In while loop ==== get_wan_ips()"
		WAN_PARAMS=""
		#Get IPv4 address of erouter0
		WAN_IP4=`ip -4 addr show dev $WAN_IF scope global | awk '/inet/{print $2}' | cut -d '/' -f1`

		#Get IPv6 address of wan0
		WAN_IP6=`ip -6 addr show dev $WAN_IF scope global | awk '/inet/{print $2}' | cut -d '/' -f1`

		if [ "$WAN_IP4" == "" ] && [ "$WAN_IP6" == "" ]; then
			echo "wan_ssh.sh: erouter0 doesn't have ipv4 or ipv6 IPs yet, sleep 60 sec and retry.."
			sleep 60
		else
			if [ "$WAN_IP4" != "" ] ; then
				WAN_PARAMS="-p [${WAN_IP4}]:$PORT"
			fi
			if [ "$WAN_IP6" != "" ] ; then
				WAN_PARAMS="$WAN_PARAMS -p [${WAN_IP6}]:$PORT"
			fi
			#Breaking loop, because we have now v4 or v6 or both
			#echo "Break while loop ==== get_wan_ips()"
			break
		fi
	done
}

start_dropbear_wan()
{
	get_wan_ips
	DROPBEAR_PARAMS_1="/tmp/.dropbear/dropcfg1_wanssh"
	DROPBEAR_PARAMS_2="/tmp/.dropbear/dropcfg2_wanssh"
        if [ ! -d '/tmp/.dropbear' ]; then
            echo "wan_ssh.sh: need to create dropbear dir "
            mkdir -p /tmp/.dropbear
        fi
        if [ ! -f $DROPBEAR_PARAMS_1 ]; then
	    getConfigFile $DROPBEAR_PARAMS_1
        fi
        if [ ! -f $DROPBEAR_PARAMS_2 ]; then
	    getConfigFile $DROPBEAR_PARAMS_2
        fi
        echo "WAN_PARAMS: $WAN_PARAMS"
        #RDKB-16251
	dropbear -E -s -b /etc/sshbanner.txt -a $WAN_PARAMS -r $DROPBEAR_PARAMS_1 -r $DROPBEAR_PARAMS_2 2>/dev/null
}

add_v4firewall_rule()
{
	#insert ipv4_firewall rule to accept ssh connection
	iptables -I INPUT -i $WAN_IF -p tcp -m tcp --dport $PORT -j SSH_FILTER
}

add_v6firewall_rule()
{
	#insert ipv6_firewall rule to accept ssh connection
	ip6tables -I INPUT -i $WAN_IF -p tcp -m tcp --dport $PORT -j SSH_FILTER
}

remove_v4firewall_rule()
{
        #insert ipv4_firewall rule to DROP ssh connection
        iptables -D INPUT -i $WAN_IF -p tcp -m tcp --dport $PORT -j SSH_FILTER
}

remove_v6firewall_rule()
{
        #insert ipv6_firewall rule to DROP ssh connection
        ip6tables -D INPUT -i $WAN_IF -p tcp -m tcp --dport $PORT -j SSH_FILTER
}

start_wan_ssh_service()
{
	while [ $loop -eq 1 ]
	do
		WAN_IF=$(getWanInterfaceName)
		#echo "In while loop ==== start_wan_ssh_service()"
		check_WAN_IP4=`ip -4 addr show dev $WAN_IF scope global | awk '/inet/{print $2}' | cut -d '/' -f1`
		check_WAN_IP6=`ip -6 addr show dev $WAN_IF scope global | awk '/inet/{print $2}' | cut -d '/' -f1`

		if [ "$check_WAN_IP4" != "" ] ; then
			check_dropbear_v4=`ps w| grep dropbear | grep -E "$check_WAN_IP4" | grep -E "$PORT"`
		fi
		if [ "$check_WAN_IP6" != "" ] ; then
			check_dropbear_v6=`ps ww| grep dropbear | grep -E "$check_WAN_IP6" | grep -E "$PORT"`
		fi

		check_v4_rule=`iptables-save | grep -E "$WAN_IF -p tcp -m tcp --dport $PORT -j SSH_FILTER"`
		check_v6_rule=`ip6tables-save | grep -E "$WAN_IF -p tcp -m tcp --dport $PORT -j SSH_FILTER"`


		#echo "WAN_IP4: $check_WAN_IP4"
		#echo "WAN_IP6: $check_WAN_IP6"
		#echo "PORT: $PORT"

		#echo "dropbear_v4: $check_dropbear_v4"
		#echo "dropbear_v6: $check_dropbear_v6"

		#echo "v4_rule: $check_v4_rule"
		#echo "v6_rule: $check_v6_rule"

		if [ "$check_dropbear_v4" == "" ] && [ "$check_dropbear_v6" == "" ];then
			echo "wan_ssh.sh: dropbear NOT running on WAN ips. Starting now.."
			start_dropbear_wan
                elif [ "$check_dropbear_v4" != "" ] && [ "$check_dropbear_v6" != "" ];then
			echo "wan_ssh.sh: dropbear running on erouter0 v4 and v6 ips. No action needed."
		else
			if [ "$check_WAN_IP6" != "" ] && [ "$check_WAN_IP4" != "" ];then
				echo "wan_ssh.sh: dropbear is running on either v4 or v6, but now erouter has both ips. Restarting dropbear"
				#kill existing dropbear service and start new
				dropbear_wan_pid=`ps w| grep dropbear | grep -E "$check_WAN_IP4|$check_WAN_IP6 | grep -E "$PORT" " | awk '{print $1}'`
				echo $dropbear_wan_pid|xargs kill -9
				start_dropbear_wan
			else
				echo "wan_ssh.sh: dropbear running in either v4 or v6, not ready for both"
			fi
		fi

		if [ "$check_v4_rule" == "" ];then
			echo "wan_ssh.sh: v4 rule is missing in iptables, adding now"
			add_v4firewall_rule
		fi

		if [ "$check_v6_rule" == "" ];then
			echo "wan_ssh.sh: v6 rule is missing in ip6tables, adding now"
			add_v6firewall_rule
		fi

		sleep 60
	done
}

stop_wan_ssh_service()
{
                #echo "In while loop ==== start_wan_ssh_service()"
                check_WAN_IP4=`ip -4 addr show dev $WAN_IF scope global | awk '/inet/{print $2}' | cut -d '/' -f1`
                check_WAN_IP6=`ip -6 addr show dev $WAN_IF scope global | awk '/inet/{print $2}' | cut -d '/' -f1`

                if [ "$check_WAN_IP4" != "" ] ; then
                        check_dropbear_v4=`ps w| grep dropbear | grep -E "$check_WAN_IP4" | grep -E "$PORT"`
                fi
                if [ "$check_WAN_IP6" != "" ] ; then
                        check_dropbear_v6=`ps ww| grep dropbear | grep -E "$check_WAN_IP6" | grep -E "$PORT"`
                fi

                check_v4_rule=`iptables-save | grep -E "$WAN_IF -p tcp -m tcp --dport $PORT -j SSH_FILTER"`
                check_v6_rule=`ip6tables-save | grep -E "$WAN_IF -p tcp -m tcp --dport $PORT -j SSH_FILTER"`


                #echo "WAN_IP4: $check_WAN_IP4"
                #echo "WAN_IP6: $check_WAN_IP6"
                #echo "PORT: $PORT"

                #echo "dropbear_v4: $check_dropbear_v4"
                #echo "dropbear_v6: $check_dropbear_v6"

                #echo "v4_rule: $check_v4_rule"
                #echo "v6_rule: $check_v6_rule"
                
		if [ "$check_dropbear_v4" != "" ] && [ "$check_dropbear_v6" != "" ];then
                        echo "wan_ssh.sh: dropbear running on erouter0 v4 and v6 ips."
                        if [ "$check_WAN_IP6" != "" ] && [ "$check_WAN_IP4" != "" ];then
                                echo "wan_ssh.sh: dropbear is running on either v4 or v6. Kill existing dropbear & wan_ssh.sh enable services"
                                #kill existing dropbear service
                                dropbear_wan_pid=`ps w| grep dropbear | grep -E "$check_WAN_IP4|$check_WAN_IP6 | grep -E "$PORT" " | awk '{print $1}'`
                                echo "kill dropbear_PID $dropbear_wan_pid"       
  				kill -9 $dropbear_wan_pid 
                                #kill existing wan_ssh.sh enable service
                                wan_ssh_enable_pid=`ps w| grep wan_ssh.sh | grep -E enable | awk '{print $1}'`
                                echo "kill wan_ssh_enable_PID $wan_ssh_enable_pid"
  				kill -9 $wan_ssh_enable_pid
                        else
                                echo "wan_ssh.sh: dropbear running in either v4 or v6, not ready for both"
                        fi
               		
			if [ "$check_v4_rule" != "" ];then
                        	echo "wan_ssh.sh: v4 rule is in iptables, removing it now"
                        	remove_v4firewall_rule
                	fi

                	if [ "$check_v6_rule" != "" ];then
                        	echo "wan_ssh.sh: v6 rule is in ip6tables, removing it now"
                        	remove_v6firewall_rule
                	fi

                else
                     echo "wan_ssh.sh: dropbear not running on erouter0 v4 and v6 ips and not killed."
                fi

}
######################### MAIN #######################

echo “wan_ssh.sh: WANSideSSH.Enable: $1”
WANSideSSHEnable="$1"

if [ "$WANSideSSHEnable" = "enable" ];then
   echo "wan_ssh.sh: start WANside SSH service for partner network."
   start_wan_ssh_service
elif [ "$WANSideSSHEnable" = "disable" ];then
   echo "wan_ssh.sh: stop WANside SSH service for partner network."
   stop_wan_ssh_service
fi
