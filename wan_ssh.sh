WAN_IF=erouter0
PORT=49971
loop=1
WAN_IP4=""
WAN_IP6=""

#RDKB-16251
if [ -f /etc/mount-utils/getConfigFile.sh ];then
	mkdir -p /tmp/.dropbear
	. /etc/mount-utils/getConfigFile.sh
fi

get_wan_ips()
{
	while [ $loop -eq 1 ]
	do
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
	#echo "WAN_PARAMS: $WAN_PARAMS"
	#RDKB-16251
	DROPBEAR_PARAMS_1="/tmp/.dropbear/dropcfg1$$"
	DROPBEAR_PARAMS_2="/tmp/.dropbear/dropcfg2$$"
	getConfigFile $DROPBEAR_PARAMS_1
	getConfigFile $DROPBEAR_PARAMS_2
	dropbear -E -s -b /etc/sshbanner.txt -a $WAN_PARAMS -r $DROPBEAR_PARAMS_1 -r $DROPBEAR_PARAMS_2 2>/dev/null
        rm -rf /tmp/.dropbear/*
}

add_v4firewall_rule()
{
	#insert ipv4_firewall rule to accept ssh connection
	iptables -I INPUT -i $WAN_IF -p tcp -m tcp --dport $PORT -j ACCEPT
}

add_v6firewall_rule()
{
	#insert ipv6_firewall rule to accept ssh connection
	ip6tables -I INPUT -i $WAN_IF -p tcp -m tcp --dport $PORT -j ACCEPT
}

remove_v4firewall_rule()
{
        #insert ipv4_firewall rule to DROP ssh connection
        iptables -D INPUT -i $WAN_IF -p tcp -m tcp --dport $PORT -j ACCEPT
}

remove_v6firewall_rule()
{
        #insert ipv6_firewall rule to DROP ssh connection
        ip6tables -D INPUT -i $WAN_IF -p tcp -m tcp --dport $PORT -j ACCEPT
}

start_wan_ssh_service()
{
	while [ $loop -eq 1 ]
	do
		#echo "In while loop ==== start_wan_ssh_service()"
		check_WAN_IP4=`ip -4 addr show dev $WAN_IF scope global | awk '/inet/{print $2}' | cut -d '/' -f1`
		check_WAN_IP6=`ip -6 addr show dev $WAN_IF scope global | awk '/inet/{print $2}' | cut -d '/' -f1`

		if [ "$check_WAN_IP4" != "" ] ; then
			check_dropbear_v4=`ps w| grep dropbear | grep -E "$check_WAN_IP4" | grep -E "$PORT"`
		fi
		if [ "$check_WAN_IP6" != "" ] ; then
			check_dropbear_v6=`ps w| grep dropbear | grep -E "$check_WAN_IP6" | grep -E "$PORT"`
		fi

		check_v4_rule=`iptables-save | grep -E "$WAN_IF -p tcp -m tcp --dport $PORT -j ACCEPT"`
		check_v6_rule=`ip6tables-save | grep -E "$WAN_IF -p tcp -m tcp --dport $PORT -j ACCEPT"`


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
                        check_dropbear_v6=`ps w| grep dropbear | grep -E "$check_WAN_IP6" | grep -E "$PORT"`
                fi

                check_v4_rule=`iptables-save | grep -E "$WAN_IF -p tcp -m tcp --dport $PORT -j ACCEPT"`
                check_v6_rule=`ip6tables-save | grep -E "$WAN_IF -p tcp -m tcp --dport $PORT -j ACCEPT"`


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
