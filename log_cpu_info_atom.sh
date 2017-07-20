mpstat -P ALL 1 >> /rdklogs/logs/mpstat.log &
sleep 1

PID=`ps | grep mpstat | grep -v grep | awk '{print $1}'`
if [[ "" !=  "$PID" ]]; then
    #echo "killing $PID"
    kill -9 $PID
fi
