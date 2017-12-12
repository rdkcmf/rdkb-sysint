#!/bin/sh

files_to_backup="/nvram2"
dest_to_copy="/nvram/scratch_pad"
function create_scratchpad_area(){
         mkdir -p /nvram/scratch_pad
}

function generate_key(){
	#Generate the key.
	if [ ! -f /tmp/kfqimholywkj/key.nvram ]; then
		echo "Creating the key on fly under /tmp" >> /tmp/encryption.txt
		mkdir -p /tmp/kfqimholywkj
                configparamgen jx /etc/kclxkwbzj.oed /tmp/fwGS.bin
                /usr/bin/ecfsk 2k > /tmp/kfqimholywkj/key.nvram
                chmod 400 /tmp/kfqimholywkj/key.nvram   
                sync
	fi
}


function encryption_enable(){
CRYPT_NVRAM2=nvram2
CRYPT_NVRAM=nvram
NVRAM2_PARTITION=/dev/mmcblk0p14
NVRAM_PARTITION=/dev/mmcblk0p3
NVRAM2_DIR=/nvram2
NVRAM_DIR=/nvram
CRYPT_MAPPER_NVRAM2=/dev/mapper/$CRYPT_NVRAM2
CRYPT_MAPPER_NVRAM=/dev/mapper/$CRYPT_NVRAM
        mount | grep  -w "nvram2" | grep "mmc" > /dev/null
	if [ $? -eq 0 ]; then
                echo "Need to encrypt the nvram2 partition in next phase " >> /tmp/encryption.txt
                : '
                #TODO: enable the script for encrypting partition in Phase2 
        	#Prepare scratch pad area
                create_scratchpad_area
                partition_name=$CRYPT_NVRAM2
		hostname=$(hostname -s)
		archive_file="$hostname-$partition_name.tgz"

		tar cpzf $dest_to_copy/$archive_file $files_to_backup
		tar -tvf $dest_to_copy/$archive_file >> /tmp/encryption.txt
		sync
		echo "Backup successfull !!! " >> /tmp/encryption.txt
		echo $(tar -tf $dest_to_copy/$archive_file) >> /tmp/encryption.txt

		generate_key

		#umount -v /nvram2
                umount -v $NVRAM2_DIR
		if [ $? -ne 0 ] ; then
			echo "Unmounting $NVRAM2_DIR failed" >> /tmp/encryption.txt
                        echo "Encryption of $NVRAM2_DIR partition failed" >> /tmp/encryption.txt
		else
			echo "Unmounting $NVRAM2_DIR success" >> /tmp/encryption.txt

	        	#Encrypt /dev/mmcblk0p14 now
		        command="cryptsetup -q --cipher aes --hash sha512 --offset=0 -d 2048 -d /tmp/kfqimholywkj/key.nvram open --type plain $NVRAM2_PARTITION $CRYPT_NVRAM2"
                        $command
                        cryptsetup -v status $CRYPT_MAPPER_NVRAM2 >> /tmp/encryption.txt
	                echo "Formatting the drive " >> /tmp/encryption.txt
                        mkfs.ext3 $CRYPT_MAPPER_NVRAM2
                        mount $CRYPT_MAPPER_NVRAM2  $NVRAM2_DIR
                        echo "Mouting  $CRYPT_MAPPER_NVRAM2 to $NVRAM2_DIR ext3 partition : Success" >> /tmp/encryption.txt

		        echo "Untarring the backup to $NVRAM2_DIR " >> /tmp/encryption.txt
		        tar -xpzf $dest_to_copy/$archive_file -C / 
	                sync
                fi
                '
        else
                #After reboot procedure
                generate_key

		command="cryptsetup -q --cipher aes --hash sha512 --offset=0 -d 2048 -d /tmp/kfqimholywkj/key.nvram open --type plain $NVRAM2_PARTITION $CRYPT_NVRAM2"
                $command 
                mount $CRYPT_MAPPER_NVRAM2  $NVRAM2_DIR 
                if [ $? -eq 0 ]; then
                    echo "mounted $NVRAM2_DIR successfully" >> /tmp/encryption.txt
                else
                   echo "mounting $NVRAM2_DIR failed" >> /tmp/encryption.txt      
                fi                   
	fi
        #support for mounting encrypted /nvram partition
        mount | grep  -w "nvram" | grep "mmc" > /dev/null
        if [ $? -eq 0 ]; then
            echo "Need to encrypt the nvram partition in next phase" >> /tmp/encryption.txt
        else
            generate_key 
            command="cryptsetup -q --cipher aes --hash sha512 --offset=0 -d 2048 -d /tmp/kfqimholywkj/key.nvram open --type plain $NVRAM_PARTITION $CRYPT_NVRAM"
            $command
            mount $CRYPT_MAPPER_NVRAM  $NVRAM_DIR
            if [ $? -eq 0 ]; then
                echo "mounted $NVRAM_DIR successfully" >> /tmp/encryption.txt
            else
                echo "mounting $NVRAM_DIR failed" >> /tmp/encryption.txt
            fi
        fi
}

if [ -f /usr/sbin/cryptsetup ]; then
       encryption_enable
else
      echo "/usr/sbin/cryptsetup not available. So no encryption." >> /tmp/encryption.txt
fi


