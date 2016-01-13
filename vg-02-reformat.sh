#!/usr/bin/env bash
set -o verbose
set -o errexit

# Zero everything to save space
mkswap /dev/sda2
SWAPUUID=$(blkid /dev/sda2 -s UUID | cut -f 2 -d '=' | tr -d '"' )
echo "UUID=${SWAPUUID} none            swap    sw              0       0" >> /etc/fstab

rm -rf /var/log/installer/

# Clean up unused space
dd if=/dev/zero of=/EMPTY bs=64k || true
rm -f /EMPTY
sync

# Only resize to about 60 G to prevent the VM growing out of control
# It's very easy to rerun resize2fs to get more space, when necessary
resize2fs /dev/sda1 60G

# Reset to vagrant insecure key
echo "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key" \
> /home/vagrant/.ssh/authorized_keys

systemctl poweroff