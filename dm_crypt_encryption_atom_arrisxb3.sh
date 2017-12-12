#!/bin/sh


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
CRYPT_NVRAM_ATOM=nvramatom
NVRAM_PARTITION=/dev/mmcblk0p11
NVRAM_DIR=/nvram
CRYPT_MAPPER_NVRAM_ATOM=/dev/mapper/$CRYPT_NVRAM_ATOM
        #support for mounting encrypted /nvram partition
        mount | grep  -w "nvram" | grep "mmc" > /dev/null
        if [ $? -eq 0 ]; then
            echo "Need to encrypt the nvram partition in next phase" >> /tmp/encryption.txt
        else
            generate_key 
            command="cryptsetup -q --cipher aes --hash sha512 --offset=0 -d 2048 -d /tmp/kfqimholywkj/key.nvram open --type plain $NVRAM_PARTITION $CRYPT_NVRAM_ATOM"
            $command
            mount $CRYPT_MAPPER_NVRAM_ATOM  $NVRAM_DIR
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


