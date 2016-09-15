#!/bin/sh

LOG_FOLDER="/rdklogs/logs"
ATOMCONSOLELOGFILE="$LOG_FOLDER/AtomConsolelog.txt.0"

echo_t()
{
        echo "`date +"%y%m%d-%T.%6N"` $1"
}

exec 3>&1 4>&2 >>$ATOMCONSOLELOGFILE 2>&1


