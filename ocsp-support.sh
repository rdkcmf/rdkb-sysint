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

. /etc/device.properties

if [ -f /etc/include.properties ];then
    . /etc/include.properties
fi

OCSP_LOG_FILE="$LOG_PATH/ocsp-support.log"
StatusOCSPSTAPLE=`syscfg get EnableOCSPStapling`
if [ -z "$StatusOCSPSTAPLE" ]; then
    StatusOCSPSTAPLE=`dmcli eRT getv Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.CRL.Enable | grep value | awk '{print $5}'`
fi

StatusOCSPCA=`syscfg get EnableOCSPCA`
if [ -z "$StatusOCSPCA" ]; then
    StatusOCSPCA=`dmcli eRT getv Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.CRL.DirectOCSP | grep value | awk '{print $5}'`
fi


echo "status of RFC StatusOCSPSTAPLE $StatusOCSPSTAPLE StatusOCSPCA $StatusOCSPCA" >> $OCSP_LOG_FILE

if [ "$StatusOCSPSTAPLE" = "true" ]; then
    echo "[OCSPSTAPLE] Enabled" >> $OCSP_LOG_FILE
    touch /tmp/.EnableOCSPStapling
else
    echo "[OCSPSTAPLE] Disabled" >> $OCSP_LOG_FILE
    if [ -f /tmp/.EnableOCSPStapling ]; then
        rm -f /tmp/.EnableOCSPStapling
    fi
fi

if [ "$StatusOCSPCA" = "true" ]; then
    echo "[OCSPCA] Enabled" >> $OCSP_LOG_FILE
    touch /tmp/.EnableOCSPCA
else
    echo "[OCSPCA] Disabled" >> $OCSP_LOG_FILE
    if [ -f /tmp/.EnableOCSPCA ]; then
        rm -f /tmp/.EnableOCSPCA
    fi
fi
