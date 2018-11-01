#!/bin/sh

source /etc/device.properties
source /etc/log_timestamp.sh

CONSOLE_LOG_FILE="/rdklogs/logs/Consolelog.txt.0"

if [ "$MODEL_NUM" == "TG3482G" ];then
	factoryPartnerId=`arris_rpc_client arm nvm_get cust_id`
fi

if [ "$MODEL_NUM" == "CGM4140COM" ];then
	factory_nvram -r
	factoryPartnerId=`cat /tmp/factory_nvram.data |grep Customer | tr '[A-Z]' '[a-z]' | cut -d' ' -f2`
fi

echo_t "Factory Partner_ID returned from the platform is: $factoryPartnerId" >> "$CONSOLE_LOG_FILE"

rdkb_partner_id=`syscfg get PartnerID`
echo_t "RDKB Partner_ID returned from the syscfg.db is: $rdkb_partner_id" >> "$CONSOLE_LOG_FILE"
