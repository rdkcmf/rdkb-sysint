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

source /etc/device.properties
source /etc/log_timestamp.sh
source /lib/rdk/t2Shared_api.sh


CONSOLE_LOG_FILE="/rdklogs/logs/Consolelog.txt.0"

if [ "$BOX_TYPE" = "XB6" -a "$MANUFACTURE" = "Arris" ];then
	factoryPartnerId=`arris_rpc_client arm nvm_get cust_id`
fi

if [ "$BOX_TYPE" = "XB6" -a "$MANUFACTURE" = "Technicolor" ];then
	factory_nvram -r
    factoryPartnerId=`grep Customer /tmp/factory_nvram.data | tr '[A-Z]' '[a-z]' | cut -d' ' -f2`
fi

echo_t "Factory Partner_ID returned from the platform is: $factoryPartnerId" >> "$CONSOLE_LOG_FILE"
t2ValNotify "factoryPartnerid_split" "$factoryPartnerId"


rdkb_partner_id=`syscfg get PartnerID`
echo_t "RDKB Partner_ID returned from the syscfg.db is: $rdkb_partner_id" >> "$CONSOLE_LOG_FILE"
t2ValNotify "syscfg_partner_split" "$rdkb_partner_id"
