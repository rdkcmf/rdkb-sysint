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
#
##########################################################################
## Script to perform dynamic whitelisting of servers obtained from RFC
##########################################################################

. /etc/device.properties
. /etc/include.properties

if [ -f /lib/rdk/utils.sh  ]; then
   . /lib/rdk/utils.sh
fi

IPV6_BIN="/usr/sbin/ip6tables -w "
IPV4_BIN="/usr/sbin/iptables -w "
PROD_SSH_WHITELIST_FILE="/etc/dropbear/prodMgmtIps.cfg"

rfclog ()
{
   echo "$1" >> $LOG_PATH/dcmrfc.log
}

REFRESH=$1

##########################################################################
#APPLICATION START
##########################################################################

#Create lock file to prevent multiple instances of this script
touch /tmp/.rfcLock

isForwardSSHEnabled=`syscfg show | grep ForwardSSH |awk -F '=' '{print $2}'`

if [ "x$REFRESH" = "xSSH_REFRESH" ]; then
   #Flush SSH_FILTER chain
   rfclog "Refreshing SSH_FILTER rules"
   $IPV6_BIN -F SSH_FILTER
   $IPV4_BIN -F SSH_FILTER
   #Whitelist RFC SSH IP's
   SSH_WHITELIST_FILE="$(ls /tmp/RFC/.RFC_* | grep -i sshwhitelist)"
   
   rfclog "SSH Dynamic Whitelist Address : "
   while read line
   do
       case $line in
           *\:*\:* ) ## IPv6 IP
             if $isForwardSSHEnabled;then
                 $IPV6_BIN -A SSH_FILTER -s $line -j ACCEPT
                 rfclog "SSH IPv6 Address : $line"
             fi
             ;;
           *\.*\.* ) ## IPv4 IP
             if $isForwardSSHEnabled;then
                 $IPV4_BIN -A SSH_FILTER -s $line -j ACCEPT
                 rfclog "SSH IPv4 Address : $line"
             fi
             ;;
       esac
   done < $SSH_WHITELIST_FILE


   rfclog "SSH Static Whitelist Address : "
   while read line
   do
             echo $line | grep -i "#" > /dev/null
             if [ $? -eq 0 ]; then
                continue
             fi
             case $line in
               *\:*\:* ) ## IPv6 IP
                 if $isForwardSSHEnabled;then
                     $IPV6_BIN -A SSH_FILTER -s $line -j ACCEPT
                     rfclog "SSH IPv6 Address : $line"
                 fi
                 ;;
               *\.*\.* ) ## IPv4 IP
                 if $isForwardSSHEnabled;then
                     $IPV4_BIN -A SSH_FILTER -s $line -j ACCEPT
                     rfclog "SSH IPv4 Address : $line" 
                 fi
                 ;;
             esac
    done < $PROD_SSH_WHITELIST_FILE
    
    #Drop other SSH packets
    $IPV6_BIN -A SSH_FILTER -j LOG_SSH_DROP

    #Whitelist ARM & ATOM IP's
    if [ ! -z "$ATOM_INTERFACE_IP" ]; then
        $IPV4_BIN -A SSH_FILTER -s $ATOM_INTERFACE_IP -j ACCEPT
    fi 
    if [ ! -z "$ARM_INTERFACE_IP" ]; then
        $IPV4_BIN -A SSH_FILTER -s $ARM_INTERFACE_IP -j ACCEPT
    fi

    #Drop other SSH packets
    $IPV4_BIN -A SSH_FILTER -j LOG_SSH_DROP
    rfclog "SSH Whitelisting done" 
fi

rm /tmp/.rfcLock
