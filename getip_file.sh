#!/bin/sh -

/sbin/ifconfig eth0 | /bin/grep 'inet addr:' | /usr/bin/cut -d: -f2 | /usr/bin/awk '{ print "CONTAINER_LIGHTTPD_IP="\$1}' > /tmp/ip_file.sh
