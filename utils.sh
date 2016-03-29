#!/bin/sh
# Scripts having common utility functions

source /fss/gw/etc/utopia/service.d/log_env_var.sh
source /etc/utopia/service.d/log_capture_path.sh

CMINTERFACE="wan0"
WANINTERFACE="erouter0"

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
     mac=`ifconfig $WANINTERFACE | grep HWaddr | cut -d " " -f7 | sed 's/://g'`
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
    wanIP=`ifconfig $WANINTERFACE | grep "inet addr" | grep -v inet6 | cut -f2 -d: | cut -f1 -d" "`
    echo $wanIP
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
    mac=`ifconfig $CMINTERFACE | grep HWaddr | cut -d " " -f11`
    echo $mac
} 

## Get eSTB mac address 
getErouterMacAddress()
{
    erouterMac=`ifconfig $WANINTERFACE | grep HWaddr | cut -d " " -f7`
    echo $erouterMac
}

rebootFunc()
{
    #sync
    reboot
}

# Return system uptime in seconds
Uptime()
{
     cat /proc/uptime | awk '{ split($1,a,".");  print a[1]; }'
}

## Get Model No of the box
getModel()
{
  echo `cat /fss/gw/version.txt | grep ^imagename= | cut -d "=" -f 2 | cut -d "_" -f 1`
}


