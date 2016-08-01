#!/bin/sh

echo "Script called to remove the ATOM side log file contents"

LOG_FOLDER="/rdklogs/logs/"
cd $LOG_FOLDER

	file_list=`ls $LOG_PATH`
	for file in $file_list
	do
		> $file
	done
