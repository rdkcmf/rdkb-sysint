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

IPV6_BIN="/usr/sbin/ip6tables"
IPV4_BIN="/usr/sbin/iptables"

if [ -z "$CM_INTERFACE" ]; then
    CM_INTERFACE="wan0"
fi

CM_IP=`getCMIPAddress`
case $CM_IP in 
       *\:*\:* ) ## IPv6 IP
             IP_MODE="ipv6"
             ;;
       *\.*\.* ) ## IPv4 IP
             IP_MODE="ipv4"
             ;;
esac

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

if [ "x$REFRESH" = "xSSH_REFRESH" ]; then
   if [ "x$IP_MODE" == "xipv6" ]; then
      rfclog "Box is in IPv6 mode. Refreshing Ipv6 rules"
      #Flush SSH_FILTER chain
      $IPV6_BIN -F SSH_FILTER

      #Whitelist RFC SSH IP's
      SSH_WHITELIST_FILE="$(ls /tmp/RFC/.RFC_* | grep -i sshwhitelist)"
      while read line
      do
          $IPV6_BIN -A SSH_FILTER -s $line -j ACCEPT
      done < $SSH_WHITELIST_FILE

      #Enable SSH only from whitelisted source for all builds
         PROD_SSH_WHITELIST_FILE="/etc/dropbear/prodMgmtIps.cfg"
         ipv6_enable=0
         while read line
         do
             echo $line | grep -i "#" > /dev/null
             if [ $? -eq 0 ]; then
                continue
             fi
             echo $line | grep -i ipv6 > /dev/null
             if [ $? -eq 0 ]; then
                ipv6_enable=1
                continue
             fi
             echo $line | grep -i ipv4 > /dev/null
             if [ $? -eq 0 ]; then
                break
             fi
             if [ $ipv6_enable -eq 1 ]; then
                $IPV6_BIN -A SSH_FILTER -s $line -j ACCEPT
             fi
         done < $PROD_SSH_WHITELIST_FILE

      #Drop other SSH packets
      $IPV6_BIN -A SSH_FILTER -j LOG_SSH_DROP
   elif [ "x$IP_MODE" == "xipv4" ]; then
      rfclog "Box in IPv4 mode. Refreshing Ipv4 rules"
      #Flush SSH_FILTER chain
      $IPV4_BIN -F SSH_FILTER

      #Whitelist ARM & ATOM IP's
      $IPV4_BIN -A SSH_FILTER -s $ATOM_INTERFACE_IP -j ACCEPT
      $IPV4_BIN -A SSH_FILTER -s $ARM_INTERFACE_IP -j ACCEPT

      #Whitelist RFC SSH IP's
      SSH_WHITELIST_FILE="$(ls /tmp/RFC/.RFC_* | grep -i sshwhitelist)"
      while read line
      do
          $IPV4_BIN -A SSH_FILTER -s $line -j ACCEPT
      done < $SSH_WHITELIST_FILE

      #Enable SSH only from whitelisted source for all builds
         PROD_SSH_WHITELIST_FILE="/etc/dropbear/prodMgmtIps.cfg"
         ipv4_enable=0
         while read line
         do
             echo $line | grep -i "#" > /dev/null
             if [ $? -eq 0 ]; then
                continue
             fi
             echo $line | grep -i ipv4 > /dev/null
             if [ $? -eq 0 ]; then
                ipv4_enable=1
                continue
             fi
             if [ $ipv4_enable -eq 1 ]; then
                $IPV4_BIN -A SSH_FILTER -s $line -j ACCEPT
             fi
         done < $PROD_SSH_WHITELIST_FILE

      #Drop other SSH packets
      $IPV4_BIN -A SSH_FILTER -j LOG_SSH_DROP
   fi
   rfclog "SSH Whitelisting done" 
fi

rm /tmp/.rfcLock
