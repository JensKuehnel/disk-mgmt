disk-mgmt.sh is a tool to test and log data a disk.

The infos and test results are added to a LOGDIR. 
With the help of git or a sync solution this helps you to keep an overview
over the used disks and there health status.

Default LOGDIR is /etc/disk-mgmt/

Tested and working with SATA-HDD, SATA-SSD and NVME-SSD.
USB-HDD and USB-SSD are only supported when the command works with USB smartctl,
Because most USB adapter as not passing thourgh the native commands.

Needs:
 - smartctl
 - hdparm
 - lsblk
 - systemd-udev (udevadm)
 - blkdiscard
 - badblocks


