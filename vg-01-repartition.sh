#!/usr/bin/env bash
set -o errexit

echo "Waiting for kube-dns to show up"
until $(kubectl --namespace=kube-system get pods | grep -q '^kube-dns.*3/3.*$'); do
    printf '.'
    sleep 5
done
set -o verbose

swapoff /dev/sda5

SWAPUUID=$(blkid /dev/sda5 -s UUID | cut -f 2 -d '=' | tr -d '"' )

# Clean up unused space
dd if=/dev/zero of=/dev/sda5 bs=64k || true

# to create the partitions programatically (rather than manually)
# we're going to simulate the manual input to fdisk
# The sed script strips off all the comments so that we can
# document what we're doing in-line with the actual commands
# Note that a blank line (commented as "defualt" will send a empty
# line terminated with a newline to take the fdisk default.
#
# Device     Boot    Start      End  Sectors  Size Id Type
# /dev/sda1  *        2048 19816447 19814400  9.5G 83 Linux
# /dev/sda2       19818494 20764671   946178  462M  5 Extended
# /dev/sda5       19818496 20764671   946176  462M 82 Linux swap / Solaris

sed -e 's/\t\([\+0-9a-zA-Z]*\)[ \t].*/\1/' << EOF | fdisk /dev/sda || true
	d #
	1 #
	d #
	2 #
	n # new
	p # primary
	1 #
	  # default - start at beginning of disk
	+119G # 119 GiB
	n # new
	p # primary
	2 # 2
	  # default, start immediately after preceding partition
	  # default, extend partition to end of disk
	a # make a partition bootable
	1 # bootable partition is partition 1 -- /dev/sda1
	t # change type
	2 # for swap
	82 # Linux swap
	p # print the in-memory partition table
	w # write the partition table
EOF

sed -i "/${SWAPUUID}/d" /etc/fstab
