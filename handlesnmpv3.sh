#!/bin/sh
##########################################################################
# If not stated otherwise in this file or this component's Licenses.txt
# file the following copyright and licenses apply:
#
# Copyright 2019 RDK Management
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

#get wan status event
WAN_STATUS=`sysevent get wan-status`
SNMPV3=`syscfg get V3Support`
SYSTEMCTL=/bin/systemctl

if [ "$WAN_STATUS" = "started" ] && [ "$SNMPV3" = "true" ]; then
    if [ -f $SYSTEMCTL ]; then
        systemctl restart snmpd.service
    else 
        echo "Unable to restart snmpd.service. /bin/systemctl file not found." >> /rdklogs/logs/ArmConsolelog.txt.0
    fi
fi
