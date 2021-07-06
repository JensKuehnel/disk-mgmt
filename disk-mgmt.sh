#!/bin/bash
#
# vim:ts=5:sw=5:expandtab
# we have a spaces softtab, that ensures readability with other editors too

# disk-mngt.sh is a tool to test and log data about a pool of disk.
# infos and testresults are added to a LOGDIR. It is possible to create
# a database with diskinformation and sync it via git or other sync.
# Default LOGDIR is /etc/disk-mgmt/
#
# tested and fully supported are SATA-HDD, SATA-SSD and NVME-SSD.
# USB-HDD and USB-SSD are only supported when the command works with USB
# smartctl only works with some USB converters


#License: GPLv3, see http://www.fsf.org/licensing/licenses/info/GPLv2.html

# Please note:  USAGE WITHOUT ANY WARRANTY, THE SOFTWARE IS PROVIDED "AS IS".
# USE IT AT your OWN RISK!
# Seriously! The threat is you run this code on your computer and input could be /
# is being supplied via untrusted sources.
#
#
# exit-codes
# 0 succesfull execution
# 1 subcommand not found
# 2 disk not found
# 3 not run as root
# 4 wrong number of arguments
# 5 secure erase not supported
# 6 disk frozen, secure erase not possible
# 7 discard not supported

LOGDIR=/etc/disk-mgmt/
LOGDATE=$(date +%Y%m%d-%H%M%S)


help() {
cat << EOF 
Usage:   $0 COMMAND DISK
Example: $0 log-smart sda

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!! Unix rules applies, no questions ask.
!! Will delete data without "are you sure" questions!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

Valid commands are:
 - info (shows info about the disk)
 - ls (show entries in configdir)
 - log (show logfile)
 - edit-log (edit logfile file, for things like former usage or dmesg output)
 - edit-location (edit location file)
 - smart-log (Write current SMART data to logfile)
 - smart-check-long (run smartctl -t long and wait until finished)
 - secure-erase (Uses hdparm to do a secure erase)
 - burn-check-fast (secure erase and badblocks-check-empty)
 - burn-check-full (secure erase and badblocks-check-full and smart-check-long)
 - badblocks-check-empty (use badblocks to verify  that harddisk is empty)
 - badblocks-single (use badblocks to write 00 and verify)
 - badblocks-full (use badblocks to 4 times write and verify)
 - full-trim (send trim command to empty SSD)
 - full-trim-verify (trim SSD and verify that empty)
EOF
}

run-command() {
echo "$1" started at "$LOGDATE" | tee -a "$LOGFILEDIR/$1-$LOGDATE"
$2
RETURN=$?
if test $RETURN -eq 0
then
     echo "$1 finished sucessfully at $(date +%Y%m%d-%H%M%S)" |
          tee -a "$LOGFILEDIR/$1-$LOGDATE"
else
     echo "$1 finished with error $RETURN at $(date +%Y%m%d-%H%M%S)" |
          tee -a "$LOGFILEDIR/$1-$LOGDATE"
fi

}

edit-file() {
"${EDITOR:-vim}" "$LOGFILEDIR/$1"
}

smart-log(){
smartctl -a "/dev/$DISK" > "$LOGFILEDIR/smart-$LOGDATE"
}

smart-wait(){
OLD_SMART_PERCENTAGE=100
## TODO Fix things so we don't need to have the first test
while SMART_PERCENTAGE=$(smartctl -a "/dev/$DISK" | grep ' of test remaining.' | sed -e 's:%.*::' | tr -d '[:space:]')
do
	test "$SMART_PERCENTAGE" == "" && break
	if test "$OLD_SMART_PERCENTAGE" -eq "$SMART_PERCENTAGE"
	then
		sleep 60
	else
		echo "${SMART_PERCENTAGE}% done @ $(date "+%Y%m%d-%H%M%S")"
		OLD_SMART_PERCENTAGE=$SMART_PERCENTAGE
	fi
done
echo "smart check finished at $(date "+%Y%m%d-%H%M%S")"

}


smart-check-long(){
smartctl -t long "/dev/$DISK"
smart-wait
smart-log
}

secure-erase(){
if test "$SECUREERASE_TIME"
then
     :
else
     echo secure erase not supported on disk
     echo 
     exit 5

fi

hdparm -I "/dev/$DISK" >> "$LOGFILEDIR/hdparm-$LOGDATE"
if grep 'not.*frozen' "$LOGFILEDIR/hdparm-$LOGDATE" > /dev/null
then
     echo disk not frozen, continue secure erase
else
     echo disk still frozen, can\'t secure erase
     echo please see: https://ata.wiki.kernel.org/index.php/ATA_Secure_Erase
     echo 
     exit 6
fi

echo secure erase in progress, access to disk is blocked
echo process trying to access disk, e.g. pvs, hddtemp etc.
echo are blocked until it is finished
echo disk reports it takes this amount of minutes:
echo "$ID_ATA_FEATURE_SET_SECURITY_ERASE_UNIT_MIN"
echo start time is: "$LOGDATE"
echo

     hdparm --user-master u --security-set-pass Eins "/dev/$DISK"

time hdparm --user-master u --security-erase    Eins "/dev/$DISK"
RETURN=$?
if test $RETURN -eq 0
  then 
       echo secure-erase finished sucessfully at "$(date +%Y%m%d-%H%M%S)" |
            tee -a "$LOGFILEDIR/secure-erase-$LOGDATE"
  else
       echo secure-erase finished with error $RETURN at "$(date +%Y%m%d-%H%M%S)" |
            tee -a "$LOGFILEDIR/secure-erase-$LOGDATE"
  fi
}


######################################################
##
## main programm
##
######################################################



if test $UID -eq 0
then
     :
else
     echo "$0 must run as root"
     exit 3
fi

if test $# -eq 2
then
     :
else
     echo "1 command and 1 disk only"
     help
     exit 4
fi

DISK=$2
if test -b "/dev/$DISK"
then
     echo "Managing $DISK"
else
     echo "$DISK not found, aborting"
     echo
     help
     exit 2
fi


## TODO check commands available
# smartctl, hdparm, blkdiscard, badblocks, lsblk

## TODO  remove eval
eval "$(udevadm info -q env -x -n "$DISK")"

MODEL=${ID_MODEL}
SERIAL=${ID_SERIAL_SHORT}
SECUREERASE_TIME=${ID_ATA_FEATURE_SET_SECURITY_ERASE_UNIT_MIN}
DISCARD=$(lsblk -nd -o DISC-ALN "/dev/$DISK" | grep -v ' 0')
SIZE=$(lsblk -nd -o SIZE "/dev/$DISK" | tr -d " ")

#DISKINFO="$DISK $ID_MODEL $ID_SERIAL_SHORT $SIZE"
echo "disk info: $MODEL $SERIAL $SIZE"

LOGFILEDIR=$LOGDIR${MODEL}_${SERIAL}_${SIZE}
mkdir -p "$LOGFILEDIR" &> /dev/null

echo "logs are in $LOGFILEDIR"


case $1 in
     info)
	  ;;
     ls)
          ls -altr "$LOGFILEDIR/"
	  ;;
     log)
          echo Log content:
	  if test -f "$LOGFILEDIR/log"
	  then
		  cat "$LOGFILEDIR/log"
	  else
		  echo "$LOGFILEDIR/log" is empty
	  fi
          ;;
     edit-log)
          edit-file log
          ;;
     edit-location)
          edit-file location
          ;;
     smart-log)
          smart-log
          ;;
     smart-check-long)
	  smart-check-long
	  ;;
     secure-erase)
          secure-erase
          ;;
     burn-check-fast)
          secure-erase
          run-command badblocks-check-empty "badblocks -vv -t 00 /dev/$DISK"
          ;;
     burn-check-full)
          secure-erase
          run-command badblocks-check-full "badblocks -vv -w /dev/$DISK"
	  smart-check-long
          ;;
     badblocks-check-empty)
          run-command badblocks-check-empty "badblocks -vv -t 00 /dev/$DISK"
          ;;
     badblocks-single)
          run-command badblocks-single "badblocks -vv -w -t 00 /dev/$DISK"
          ;;
     badblocks-full)
          run-command badblocks-full "badblocks -vv -w /dev/$DISK"
          ;;
     full-trim)
	  if test "$DISCARD"
	  then
		  run-command full-trim "blkdiscard /dev/$DISK"
	  else
		  echo disk does not support discard
		  exit 7
	  fi
          ;;
     full-trim-verify)
	  if test "$DISCARD"
	  then
		  run-command full-trim-verify "blkdiscard /dev/$DISK"
		  run-command full-trim-verify "badblocks -vv -t 00 /dev/$DISK"
	  else
		  echo disk does not support discard
		  exit 7
	  fi
          ;;
     *)
          echo "subcommand $1 not found, please check"
          help
          #exit 1
          ;;
esac

