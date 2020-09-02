#!/bin/sh

source /etc/utopia/service.d/log_capture_path.sh
source /fss/gw/etc/utopia/service.d/log_env_var.sh
source /etc/log_timestamp.sh

SHORTS_LOG_FILE_NAME=shorts.txt.0
SHORTS_LOG_FILE_PATHNAME=${LOG_PATH}/${SHORTS_LOG_FILE_NAME}
SOCAT_PATH=/tmp/socat_dnld/usr/bin/
STUNNEL_PATH=/tmp/stunnel_dnld/usr/bin/
SOCAT_BIN=socat
STUNNEL_BIN=stunnel
DNLD_SCRIPT=/etc/rdm/downloadMgr.sh
LOG_FILE=${SHORTS_LOG_FILE_PATHNAME}
SOCAT_APP_NAME=socat_dnld
STUNNEL_APP_NAME=stunnel_dnld
VALIDATION_METHOD=openssl
PKG_EXT=ipk

# don't do anything if the feature is disabled.
isShortsDLEnabled=`syscfg get ShortsDL`
if [ "x$isShortsDLEnabled" != "xtrue" ]; then
    echo_t "shortsDL RFC disabled, SHORTS feature unavailable!!!" >> $LOG_FILE
    exit 1
fi

if [ -f "$SOCAT_PATH""$SOCAT_BIN" ]; then
    echo_t "Socat is already present, no need to download" >> $LOG_FILE
else
    counter=0
    while [ $counter -lt 3 ]
    do
        sh $DNLD_SCRIPT $SOCAT_APP_NAME "" $VALIDATION_METHOD $PKG_EXT ""
        DNLD_RES=$?
        echo_t "Socat Download is completed, result is:$DNLD_RES" >> $LOG_FILE
        if [ $DNLD_RES -eq 0 ];then
            echo_t "socat download is successful" >> $LOG_FILE
            break
        else
            echo_t "socat download is failed. Retrying download" >> $LOG_FILE
            counter=`expr $counter + 1`
            sleep 10
        fi
    done
fi

if [ -f "$STUNNEL_PATH""$STUNNEL_BIN" ]; then
    echo_t "Stunnel is already present, no need to download" >> $LOG_FILE
else
    sh $DNLD_SCRIPT $STUNNEL_APP_NAME "" $VALIDATION_METHOD $PKG_EXT ""
    DNLD_RES=$?
    echo_t "Stunnel Download is completed, result is:$DNLD_RES" >> $LOG_FILE
    if [ $DNLD_RES -eq 0 ]; then
        echo_t "stunnel download is successful" >> $LOG_FILE
    else
        echo_t "stunnel download has failed" >> $LOG_FILE
        exit 1
    fi
fi
exit 0

