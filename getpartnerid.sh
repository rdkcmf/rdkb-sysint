#!/bin/sh

# Function to get partner_id
getPartnerId()
{
    if [ -f "/etc/device.properties" ]
    then
        partner_id=`cat /etc/device.properties | grep PARTNER_ID | cut -f2 -d=`
        if [ "$partner_id" == "" ];then
            #Assigning default partner_id as Comcast.
            #If any device want to report differently, then PARTNER_ID flag has to be updated in /etc/device.properties accordingly
            echo "comcast"
        else
            echo "$partner_id"
        fi
    else
       echo "null"
    fi
}
