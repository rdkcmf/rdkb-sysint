#!/bin/sh
. /etc/include.properties
. /etc/device.properties
. /usr/bin/stunnelCertUtil.sh
source /etc/log_timestamp.sh

export TERM=xterm
export HOME=/home/root
LOG_FILE="$LOG_PATH/stunnel.log"

usage()
{
  echo_t "STUNNEL USAGE:  startSTunnel.sh <localport> <jumpfqdn> <umpserver> <jumpserverport> <reverseSSHArgs>"
}

if [ $# -lt 5 ]; then
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

if [ $DEVICE_TYPE == "broadband" ]; then
    DEVICE_CERT_PATH=/nvram/certs
elif [ $DEVICE_TYPE == "mediaclient" -o $DEVICE_TYPE == "hybrid" ]; then
    DEVICE_CERT_PATH=/opt/certs
else
    echo_t "STUNNEL: $DEVICE_CERT_PATH, not expected"
    DEVICE_CERT_PATH=/tmp/certs
fi

#collect the arguments
#    1) CPE's available port starting from 3000
#    2) FQDN of jump server
#    3) Port number of stunnel's server instance at jump server
LOCAL_PORT=$1
JUMP_FQDN=$2
JUMP_SERVER=$3
JUMP_PORT=$4
REVERSESSHARGS=$5

#RDM parameters
DNLD_SCRIPT=/lib/rdk/shortsDownload.sh
SOCAT_PATH=/tmp/socat_dnld/usr/bin/socat
STUNNEL_PATH=/tmp/stunnel_dnld/usr/bin/stunnel


STUNNEL_PID_FILE=/tmp/stunnel_$LOCAL_PORT.pid
REVSSH_PID_FILE=/var/tmp/rssh.pid
STUNNEL_CONF_FILE=/tmp/stunnel_$LOCAL_PORT.conf

echo  "pid = $STUNNEL_PID_FILE"           > $STUNNEL_CONF_FILE
echo "output=$LOG_FILE"   		 >> $STUNNEL_CONF_FILE
echo "debug = 7"                       	 >> $STUNNEL_CONF_FILE
echo  "[ssh]"                            >> $STUNNEL_CONF_FILE
echo  "client = yes"                     >> $STUNNEL_CONF_FILE

# Use localhost to listen on both IPv4 and IPv6
echo "accept = localhost:$LOCAL_PORT"     >> $STUNNEL_CONF_FILE
echo "connect = $JUMP_SERVER:$JUMP_PORT" >> $STUNNEL_CONF_FILE

extract_stunnel_client_cert

if [ ! -f $CERT_FILE -o ! -f $CA_FILE ]; then
    echo_t "STUNNEL: Required cert/CA file not found. Exiting..." >> $LOG_FILE
    exit 1
fi

# this might change once we get proper certificates
echo "cert = $CERT_FILE"                     			      >> $STUNNEL_CONF_FILE
echo "CAfile = $CA_FILE"                                              >> $STUNNEL_CONF_FILE
echo "verifyChain = yes"                                              >> $STUNNEL_CONF_FILE
echo "checkHost = $JUMP_FQDN"                                         >> $STUNNEL_CONF_FILE

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

# cleanup sensitive files early
rm -f $STUNNEL_CONF_FILE
rm -f $D_FILE

REVSSHPID1=`cat $REVSSH_PID_FILE`
STUNNELPID=`cat $STUNNEL_PID_FILE`

if [ -z "$STUNNELPID" ]; then
    rm -f $STUNNEL_PID_FILE
    echo_t "STUNNEL: stunnel-client failed to establish. Exiting..." >> $LOG_FILE
    exit
fi

#Starting startTunnel
/bin/sh /lib/rdk/startTunnel.sh start $REVERSESSHARGS

REVSSHPID2=`cat $REVSSH_PID_FILE`

#Terminate stunnel if revssh fails.
if [ -z "$REVSSHPID2" ] || [ "$REVSSHPID1" == "$REVSSHPID2" ]; then
    kill -9 $STUNNELPID
    rm -f $STUNNEL_PID_FILE
    echo_t "STUNNEL: Reverse SSH failed to connect. Exiting..." >> $LOG_FILE
    exit
fi

echo_t "STUNNEL: Reverse SSH pid = $REVSSHPID2, Stunnel pid = $STUNNELPID" >> $LOG_FILE

#watch for termination of ssh-client to terminate stunnel
while test -d "/proc/$REVSSHPID2"; do
     sleep 5
done

echo_t "STUNNEL: Reverse SSH session ended. Exiting..." >> $LOG_FILE
kill -9 $STUNNELPID
rm -f $STUNNEL_PID_FILE
