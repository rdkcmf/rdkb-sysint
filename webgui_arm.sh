#! /bin/sh
##########################################################################
# If not stated otherwise in this file or this component's Licenses.txt
# file the following copyright and licenses apply:
#
# Copyright 2016 RDK Management
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

#######################################################################
#   Copyright [2014] [Cisco Systems, Inc.]
# 
#   Licensed under the Apache License, Version 2.0 (the \"License\");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
# 
#       http://www.apache.org/licenses/LICENSE-2.0
# 
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an \"AS IS\" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#######################################################################


#WEBGUI_SRC=/fss/gw/usr/www/html.tar.bz2
#WEBGUI_DEST=/var/www

#if test -f "$WEBGUI_SRC"
#then
#	if [ ! -d "$WEBGUI_DEST" ]; then
#		/bin/mkdir -p $WEBGUI_DEST
#	fi
#	/bin/tar xjf $WEBGUI_SRC -C $WEBGUI_DEST
#else
#	echo "WEBGUI SRC does not exist!"
#fi

# start lighttpd
source /etc/utopia/service.d/log_capture_path.sh
source /fss/gw/etc/utopia/service.d/log_env_var.sh
REVERT_FLAG="/nvram/reverted"
LIGHTTPD_CONF="/var/lighttpd.conf"
LIGHTTPD_DEF_CONF="/etc/lighttpd.conf"

ATOM_PROXY_SERVER="192.168.251.254"

LIGHTTPD_PID=`pidof lighttpd`
if [ "$LIGHTTPD_PID" != "" ]; then
	/bin/kill $LIGHTTPD_PID
fi

HTTP_ADMIN_PORT=`syscfg get http_admin_port`
HTTP_PORT=`syscfg get mgmt_wan_httpport`
HTTP_PORT_ERT=`syscfg get mgmt_wan_httpport_ert`
HTTPS_PORT=`syscfg get mgmt_wan_httpsport`
BRIDGE_MODE=`syscfg get bridge_mode`

if [ "$BRIDGE_MODE" != "0" ]; then
    INTERFACE="lan0"
else
    INTERFACE="l2sd0.4090"
fi

cp $LIGHTTPD_DEF_CONF $LIGHTTPD_CONF

#sed -i "s/^server.port.*/server.port = $HTTP_PORT/" /var/lighttpd.conf
#sed -i "s#^\$SERVER\[.*\].*#\$SERVER[\"socket\"] == \":$HTTPS_PORT\" {#" /var/lighttpd.conf

echo "server.port = $HTTP_ADMIN_PORT" >> $LIGHTTPD_CONF
echo "server.bind = \"$INTERFACE\"" >> $LIGHTTPD_CONF

echo "\$SERVER[\"socket\"] == \"brlan0:80\" { server.use-ipv6 = \"enable\" }" >> $LIGHTTPD_CONF
echo "\$SERVER[\"socket\"] == \"wan0:80\" { server.use-ipv6 = \"enable\" }" >> $LIGHTTPD_CONF

if [ "x$HTTP_PORT_ERT" != "x" ];then
    echo "\$SERVER[\"socket\"] == \"erouter0:$HTTP_PORT_ERT\" { server.use-ipv6 = \"enable\" }" >> $LIGHTTPD_CONF
else
    echo "\$SERVER[\"socket\"] == \"erouter0:$HTTP_PORT\" { server.use-ipv6 = \"enable\" }" >> $LIGHTTPD_CONF
fi

echo "\$SERVER[\"socket\"] == \"brlan0:443\" { server.use-ipv6 = \"enable\" ssl.engine = \"enable\" ssl.pemfile = \"/etc/server.pem\" }" >> $LIGHTTPD_CONF

echo "\$SERVER[\"socket\"] == \"$INTERFACE:443\" { server.use-ipv6 = \"enable\" ssl.engine = \"enable\" ssl.pemfile = \"/etc/server.pem\" }" >> $LIGHTTPD_CONF
echo "\$SERVER[\"socket\"] == \"wan0:443\" { server.use-ipv6 = \"enable\" ssl.engine = \"enable\" ssl.pemfile = \"/etc/server.pem\" }" >> $LIGHTTPD_CONF
if [ $HTTPS_PORT -ne 0 ]
then
    echo "\$SERVER[\"socket\"] == \"erouter0:$HTTPS_PORT\" { server.use-ipv6 = \"enable\" ssl.engine = \"enable\" ssl.pemfile = \"/etc/server.pem\" }" >> $LIGHTTPD_CONF
else
    # When the httpsport is set to NULL. Always put default value into database.
    syscfg set mgmt_wan_httpsport 8081
    syscfg commit
    HTTPS_PORT=`syscfg get mgmt_wan_httpsport`
    echo "\$SERVER[\"socket\"] == \"erouter0:$HTTPS_PORT\" { server.use-ipv6 = \"enable\" ssl.engine = \"enable\" ssl.pemfile = \"/etc/server.pem\" }" >> $LIGHTTPD_CONF
fi

echo "\$SERVER[\"socket\"] == \":51515\" { 
                                                
proxy.server      =    ( \"\" =>              
                               ( \"localhost\" =>
                                 (                                      
                                  \"host\" => \"$ATOM_PROXY_SERVER\",
                                   \"port\" => 51515              
                                 )                            
                               )                              
                             )                                
}" >> $LIGHTTPD_CONF
        

echo "proxy.server      =    ( \"\" =>
                               ( \"localhost\" =>
                                 (
                                   \"host\" => \"$ATOM_PROXY_SERVER\",
                                   \"port\" => $HTTP_ADMIN_PORT
                                 )
                               )
                             ) " >> $LIGHTTPD_CONF


 
WIFIUNCONFIGURED=`syscfg get redirection_flag`
SET_CONFIGURE_FLAG=`psmcli get eRT.com.cisco.spvtg.ccsp.Device.WiFi.NotifyWiFiChanges`

iter=0
max_iter=2
while [ "$SET_CONFIGURE_FLAG" = "" ] && [ "$iter" -le $max_iter ]
do
	iter=$((iter+1))
	echo "$iter"
	SET_CONFIGURE_FLAG=`psmcli get eRT.com.cisco.spvtg.ccsp.Device.WiFi.NotifyWiFiChanges`
done
echo_t "WEBGUI : NotifyWiFiChanges is $SET_CONFIGURE_FLAG"
echo_t "WEBGUI : redirection_flag val is $WIFIUNCONFIGURED"

if [ "$WIFIUNCONFIGURED" = "true" ]
then
    if [ "$SET_CONFIGURE_FLAG" = "true" ]
    then
        while : ; do
           echo_t "WEBGUI : Waiting for PandM to initalize completely to set ConfigureWiFi flag"
           CHECK_PAM_INITIALIZED=`find /tmp/ -name "pam_initialized"`
           # This check is to see if P&M is initialized 
           if [ "$CHECK_PAM_INITIALIZED" != "" ]
           then
               echo_t "WEBGUI : CHECK_PAM_INITIALIZED is $CHECK_PAM_INITIALIZED"
               break
           fi
           sleep 2
        done

        iter=0
        max_iter=21
        while : ; do
           echo_t "WEBGUI : Waiting for network reponse to run at least once"
           # This check is to see if network response ran at least once
           if [ -f "/tmp/.gotnetworkresponse" ]
           then
               echo_t "WEBGUI : File /tmp/.gotnetworkresponse exists, break loop."
               break
           fi
           
           if [ $iter -eq $max_iter ]
           then
               echo_t "WEBGUI : Max iteration for /tmp/.gotnetworkresponse reached, break loop " 
               break
           else
               iter=$((iter+1))
           fi
           sleep 5
        done

        # Read the http response value
        NETWORKRESPONSEVALUE=`cat /var/tmp/networkresponse.txt`

        # Check if the response received is 204 from google client.
        # If the response received is 204, then we should configure local captive portal.
        # This check is to make sure that we got response from network_response.sh and not from utopia_init.sh
        # /tmp/.gotnetworkresponse is touched from network_response.sh
        if [ "$NETWORKRESPONSEVALUE" = "204" ] && [ -f "/tmp/.gotnetworkresponse" ]
        then
            if [ ! -f "/tmp/.configurewifidone" ]
            then
               echo_t "WEBGUI : WiFi is not configured, setting ConfigureWiFi to true"
               output=`dmcli eRT setvalues Device.DeviceInfo.X_RDKCENTRAL-COM_ConfigureWiFi bool TRUE`
               check_success=`echo $output | grep  "Execution succeed."`
               if [ "$check_success" != "" ]
               then
                  echo_t "WEBGUI : Setting ConfigureWiFi to true is success"
                  touch /tmp/.configurewifidone
               fi
            else
                echo_t "WEBGUI : No need to set ConfigureWiFi to true"
            fi
        fi
    else
       if [ ! -e "$REVERT_FLAG" ]
       then

          # We reached here as redirection_flag is "true". But WiFi is configured already as per notification status.
          # Set syscfg value to false now.
          echo_t "WEBGUI : WiFi is already personalized... Setting redirection_flag to false"
          syscfg set redirection_flag false
          syscfg commit
          echo_t "WEBGUI: WiFi is already personalized. Set reverted flag in nvram"	
          touch $REVERT_FLAG
       fi
    fi
fi		


#echo "\$SERVER[\"socket\"] == \"$INTERFACE:10443\" { server.use-ipv6 = \"enable\" ssl.engine = \"enable\" ssl.pemfile = \"/etc/server.pem\" server.document-root = \"/fss/gw/usr/walled_garden/parcon/siteblk\" server.error-handler-404 = \"/index.php\" }" >> /var/lighttpd.conf
#echo "\$SERVER[\"socket\"] == \"$INTERFACE:18080\" { server.use-ipv6 = \"enable\"  server.document-root = \"/fss/gw/usr/walled_garden/parcon/siteblk\" server.error-handler-404 = \"/index.php\" }" >> /var/lighttpd.conf

LOG_PATH_OLD="/var/tmp/logs/"

if [ "$LOG_PATH_OLD" != "$LOG_PATH" ]
then
	sed -i "s|${LOG_PATH_OLD}|${LOG_PATH}|g" $LIGHTTPD_CONF
fi

LD_LIBRARY_PATH=/fss/gw/usr/ccsp:$LD_LIBRARY_PATH lighttpd -f $LIGHTTPD_CONF

echo_t "WEBGUI : Set event"
sysevent set webserver started
