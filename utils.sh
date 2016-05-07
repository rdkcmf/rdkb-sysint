#!/bin/sh
# Scripts having common utility functions

source /fss/gw/etc/utopia/service.d/log_env_var.sh

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

getCMIPAddress()
{
    address=`ifconfig -a $CMINTERFACE | grep inet6 | tr -s " " | grep -v Link | cut -d " " -f4 | cut -d "/" -f1`
    if [ ! "$address" ]; then
       address=`ifconfig -a $CMINTERFACE | grep inet | grep -v inet6 | tr -s " " | cut -d ":" -f2 | cut -d " " -f1`
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
  grep ^imagename= /fss/gw/version.txt | cut -d "=" -f 2 | cut -d "_" -f 1
}

getFWVersion()
{
    grep imagename /version.txt | cut -d '=' -f2
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


