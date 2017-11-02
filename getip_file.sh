#!/bin/sh

if [ -f /lib/rdk/getipv6_container.sh ]; then
   /bin/sh /lib/rdk/getipv6_container.sh
fi

/sbin/ifconfig eth0 | /bin/grep 'inet addr:' | /usr/bin/cut -d: -f2 | /usr/bin/awk '{ print "CONTAINER_LIGHTTPD_IP="$1}' > /tmp/container_env.sh
/sbin/ifconfig eth0 | /bin/grep 'inet6 addr:.*Global' | /usr/bin/awk -F" " '{print $3}' | /usr/bin/awk -F/ '{print "CONTAINER_LIGHTTPD_IPv6="$1}' >> /tmp/container_env.sh
touch /tmp/ip_file.sh
