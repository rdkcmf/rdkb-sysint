#!/bin/sh

if [ -f "/etc/log_timestamp.sh" ];then
	source /etc/log_timestamp.sh
fi

. /etc/device.properties

CONSOLE_LOG_FILE="/rdklogs/logs/Consolelog.txt.0"

echo_t "Partner customization - START" >> "$CONSOLE_LOG_FILE"

if [ -f "/etc/device.properties" ];then
	#For partner-specifc builds we have to use the PARTNER_ID from device.properties.
	#partner_id=`cat /etc/device.properties | grep PARTNER_ID | cut -f2 -d=`
	partner_id=`echo $PARTNER_ID`
	if [ "$partner_id" != "" ];then
		echo_t "Partner customization - applying partner_id from device.properties: $partner_id " >> "$CONSOLE_LOG_FILE"
		echo_t "Partner customization - updating /nvram/.partner_ID with value: $partner_id " >> "$CONSOLE_LOG_FILE"
		echo $partner_id > /nvram/.partner_ID
		echo_t "Partner customization - updating syscfg.db with value: $partner_id " >> "$CONSOLE_LOG_FILE"
		syscfg set PartnerID "$partner_id"
		syscfg commit
		sync
		echo_t "Partner customization - COMPLETED" >> "$CONSOLE_LOG_FILE"
	else
		echo_t "Partner customization - FAILED. PartnerID is null from device.properties" >> "$CONSOLE_LOG_FILE"
	fi
else
	echo_t "Partner customization - FAILED. device.properties is missing" >> "$CONSOLE_LOG_FILE"
fi
