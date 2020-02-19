#!/bin/sh

source /etc/log_timestamp.sh

export TERM=xterm

LOG_FILE=/tmp/shortsLog.txt

usage()
{
  echo_t "USAGE:  startSTunnel.sh <ip_ver> <localip> <jumpserverip> <jumpserverport> <remoteTerminalRows> <remoteTerminalColumns>"
}

if [ $# -lt 6 ]; then
   usage
   exit 1
fi

# don't do anything if the feature is disabled.
if [ -f "/lib/rdk/shortsDownload.sh" ]; then
    isShortsDLEnabled=`syscfg get ShortsDL`
    if [ "x$isShortsDLEnabled" != "xtrue" ]; then
        echo_t "ShortsDL RFC disabled, SHORTS feature not available" >> $LOG_FILE
        exit 0
    fi
fi

#prepare things
K_DIR="/tmp/eaqafxwah"
S_FILE="/etc/ssl/certs/eaqafxwah.vmk"
D_FILE="/tmp/eaqafxwah/eaqafxwah.vmk"
mkdir -p /tmp/eaqafxwah
configparamgen jx $S_FILE $D_FILE

#collect the arguments
IP_VER=$1
LOCAL_IP=$2
JUMP_SERVER=$3
JUMP_PORT=$4
ROWS=$5
COLUMNS=$6

#RDM parameters
DNLD_SCRIPT=/lib/rdk/shortsDownload.sh
SOCAT_PATH=/tmp/socat_dnld/usr/bin/socat
STUNNEL_PATH=/tmp/stunnel_dnld/usr/bin/stunnel

#echo "got command $IP_VER $LOCAL_IP $JUMP_SERVER $JUMP_PORT $ROWS $COLUMNS" > /tmp/webpa_command

# there is no harm in using the same port as jump server as 
# interfaces are different and it was gnerated randmol anyway

STUNNEL_PID_FILE=/tmp/stunnel_pid_$JUMP_PORT.pid
STUNNEL_CONF_FILE=/tmp/stunnel_$JUMP_PORT.conf

echo  "pid = $STUNNEL_PID_FILE"           > $STUNNEL_CONF_FILE
#echo "output=/tmp/cpe_tunnelssh.log"    >> $STUNNEL_CONF_FILE
#echo "debug = 7"                        >> $STUNNEL_CONF_FILE
echo  "[ssh]"                            >> $STUNNEL_CONF_FILE
echo  "client = yes"                     >> $STUNNEL_CONF_FILE

# keep the arguments in ip ver format for clarity 
# just ipv6 might work as in most cases a bind to ipv6 includes ipv4 for most cases
if [ $IP_VER -eq 4 ] 
then
    echo "accept = 127.0.0.1:$JUMP_PORT"     >> $STUNNEL_CONF_FILE
    echo "connect = $JUMP_SERVER:$JUMP_PORT" >> $STUNNEL_CONF_FILE
else
    echo "accept = ::1:$JUMP_PORT"           >> $STUNNEL_CONF_FILE
    echo "connect = $JUMP_SERVER:$JUMP_PORT" >> $STUNNEL_CONF_FILE
fi


# this might change once we get proper certificates
echo "key = $D_FILE"                                                  >> $STUNNEL_CONF_FILE
echo "cert = /etc/ssl/certs/device_tls_cert.pem"                      >> $STUNNEL_CONF_FILE
echo "CAfile =/etc/ssl/certs/comcast-rdk-revshell-server-ca.cert.pem" >> $STUNNEL_CONF_FILE
echo "verifyChain = yes"                                              >> $STUNNEL_CONF_FILE
echo "checkHost = $JUMP_SERVER"                                       >> $STUNNEL_CONF_FILE 

if [ -f "/usr/bin/stunnel" ]; then
    /usr/bin/stunnel $STUNNEL_CONF_FILE
elif [ -f $STUNNEL_PATH ]; then
    $STUNNEL_PATH $STUNNEL_CONF_FILE
else
    # Ideally shorts(socat and stunnel) packages should download at bootup time.
    # In case if some problem in downloading, shorts pacakages shell download here
    echo_t "stunnel/socat not found, need to download" >> $LOG_FILE
    sh $DNLD_SCRIPT
    DNLD_RES=$?
    if [ $DNLD_RES -eq 0 ]; then
        $STUNNEL_PATH $STUNNEL_CONF_FILE
    else
        echo_t "RDM not able to download shorts packages" >> $LOG_FILE
        rm -f $STUNNEL_CONF_FILE
        rm -f $D_FILE
        exit 1
    fi
fi

if [ -f "/usr/bin/socat" ]; then
    SOCAT_PATH=/usr/bin/socat
fi

# cleanup sensitive files early
rm -f $STUNNEL_CONF_FILE
rm -f $D_FILE

if [ $IP_VER -eq 4 ] 
then
    $SOCAT_PATH -w rows=$ROWS columns=$COLUMNS exec:'bash -li',pty,stderr,setsid,sigint,sane tcp:127.0.0.1:$JUMP_PORT
else
    $SOCAT_PATH -w rows=$ROWS columns=$COLUMNS exec:'bash -li',pty,stderr,setsid,sigint,sane tcp6:[::1]:$JUMP_PORT
fi

stunnel_pid=`cat $STUNNEL_PID_FILE`
kill $stunnel_pid

