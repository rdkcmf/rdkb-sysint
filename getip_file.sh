#!/bin/sh

##################################################################################
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
################################################################################


if [ -f /lib/rdk/getipv6_container.sh ]; then
   /bin/sh /lib/rdk/getipv6_container.sh
fi

/sbin/ifconfig eth0 | /bin/grep 'inet addr:' | /usr/bin/cut -d: -f2 | /usr/bin/awk '{ print "CONTAINER_LIGHTTPD_IP="$1}' > /tmp/container_env.sh
/sbin/ifconfig eth0 | /bin/grep 'inet6 addr:.*Global' | /usr/bin/awk -F" " '{print $3}' | /usr/bin/awk -F/ '{print "CONTAINER_LIGHTTPD_IPv6="$1}' >> /tmp/container_env.sh
touch /tmp/ip_file.sh
