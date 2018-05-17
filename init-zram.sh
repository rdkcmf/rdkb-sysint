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
. /etc/device.properties

# wait for the dm system to come up
dmIsUp=1
while [ "x$dmIsUp" != "x0" ] 
do
	dmcli eRT getv Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.MEMSWAP.Enable  | grep value
	dmIsUp=$?
	sleep 10
done

#check if zram is enabled by RFC, exit if not enabled
ZRAM_RFC_ENABLE=`dmcli eRT getv Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.MEMSWAP.Enable  | grep value | cut -d ":" -f 3 | tr -d ' '`
if [ "x$ZRAM_RFC_ENABLE" != "xtrue" ]; then
    echo "zram is disabled"
    exit 1
fi

# load module
NRDEVICES=$(grep -c ^processor /proc/cpuinfo | sed 's/^0$/1/')
if modinfo zram | grep -q ' zram_num_devices:' 2>/dev/null; then
    MODPROBE_ARGS="zram_num_devices=${NRDEVICES}"
elif modinfo zram | grep -q ' num_devices:' 2>/dev/null; then
    MODPROBE_ARGS="num_devices=${NRDEVICES}"
else
    exit 1
fi
modprobe zram $MODPROBE_ARGS

# decide max percentage
max_percentage=50
if [ ! -z ${ZRAM_MEM_MAX_PERCENTAGE+x} ]; then
    echo "using max mem percentage from device.properties: $ZRAM_MEM_MAX_PERCENTAGE"
    max_percentage=${ZRAM_MEM_MAX_PERCENTAGE}
fi

# Calculate memory to use for zram (1/2 of ram)
totalmem=`LC_ALL=C free | grep -e "^Mem:" | sed -e 's/^Mem: *//' -e 's/  *.*//'`
mem=$(((totalmem * 1024) / (100/50) / ${NRDEVICES}))

echo "enabling zram with $NRDEVICES devices of $mem size each"
echo "zram_enabled_stats: $NRDEVICES,$mem"
# give enough time for module loading to finish even under high load conditions.
sleep 3

#minimum swappiness of 60 is needed for good usage of zram
echo 60 >  /proc/sys/vm/swappiness

# initialize the devices
for i in $(seq ${NRDEVICES}); do
    DEVNUMBER=$((i - 1))
    echo $mem > /sys/block/zram${DEVNUMBER}/disksize
    mkswap /dev/zram${DEVNUMBER}
    swapon -p 5 /dev/zram${DEVNUMBER}
done
