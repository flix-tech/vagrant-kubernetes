#!/bin/sh
set -o verbose
set -o errexit

ETCD_VERSION=2.3.7
KUBERNETES_VERSION=1.2.0
DOCKER_VERSION=1.12.1

NET_CIRD=10.10.0.0/24
DOCKER_CIRD=10.10.0.128/25

BRIDGE_IP=10.10.0.2
BRIDGE_MASK=255.255.255.0

PORTAL_CIRD=10.0.0.0/24
CLUSTERDNS_IP=10.0.0.10
DNS_DOMAIN=mfb.local

MACADDRESS=08:00:27:16:5e:4c

# Overwrite Vboxnameserver because of bad performance on OSX
echo "supersede domain-name-servers 8.8.8.8, 8.8.4.4;" >> /etc/dhcp/dhclient.conf
printf "nameserver 8.8.8.8\nnameserver 8.8.4.4\n" > /etc/resolv.conf

# Disable all docker networking stuff, we will set it up manually
mkdir -p /etc/systemd/system/docker.service.d/
sed -e "s%\${DOCKER_CIRD}%${DOCKER_CIRD}%" /vagrant/conf/docker-override.conf > /etc/systemd/system/docker.service.d/override.conf

# Setup the bridge for docker, we connect it with the VirtualBox network (eth1)
sed -e "s%\${BRIDGE_IP}%${BRIDGE_IP}%" -e "s%\${BRIDGE_MASK}%${BRIDGE_MASK}%" /vagrant/conf/cbr0 > /etc/network/interfaces.d/cbr0
echo hwaddress ether ${MACADDRESS} >> /etc/network/interfaces

cp /vagrant/conf/vagrant-startup.service /etc/systemd/system/vagrant-startup.service

sed -e "s%\${NET_CIRD}%${NET_CIRD}%" -e "s%\${PORTAL_CIRD}%${PORTAL_CIRD}%" /vagrant/conf/vagrant-startup.sh > /usr/bin/vagrant-startup
chmod +x /usr/bin/vagrant-startup
systemctl enable vagrant-startup
systemctl start vagrant-startup

## Configure journald
mkdir -p /var/log/journal
chgrp systemd-journal /var/log/journal
chmod g+rwx /var/log/journal
echo "SystemMaxUse=1G" >> /etc/systemd/journald.conf
# Give the vagrant user full access to the journal
usermod -a -G systemd-journal vagrant
# Remove rsyslog
apt-get --quiet --yes --force-yes purge rsyslog


# docker
echo "deb http://apt.dockerproject.org/repo debian-jessie main" > /etc/apt/sources.list.d/docker.list
# Alternative keyserver hkp://pgp.mit.edu:80
apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
# sysdig
echo 'deb http://download.draios.com/stable/deb stable-$(ARCH)/' > /etc/apt/sources.list.d/sysdig.list
wget -qO- https://s3.amazonaws.com/download.draios.com/DRAIOS-GPG-KEY.public | apt-key add -
# Enable contrib for virtual-box-guest-additions
sed -i -e 's/main/main contrib/' /etc/apt/sources.list

export DEBIAN_FRONTEND=noninteractive

apt-get --quiet update
apt-get --quiet --yes dist-upgrade
# Install bridge-utils first, so that we can get the bridget for docker up
apt-get --quiet --yes --no-install-recommends install \
    bridge-utils ethtool htop vim curl \
    build-essential virtualbox-guest-dkms virtualbox-guest-utils # for virtualbox guest plugin
ifup cbr0
apt-get --quiet --yes --no-install-recommends install \
    docker-engine=${DOCKER_VERSION}-0~jessie \
    sysdig linux-headers-$(uname -r) bindfs # For sysdig # bindfs is for fixing NFS mount permissions

# Add vagrant user to docker group, so that vagrant can user docker without sudo
usermod -aG docker vagrant

if [ ! -f /vagrant/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz ]; then
    curl -sSL  https://github.com/coreos/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz -o /vagrant/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
fi
tar xzf /vagrant/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz --strip-components=1 etcd-v${ETCD_VERSION}-linux-amd64/etcd etcd-v${ETCD_VERSION}-linux-amd64/etcdctl
mv etcd etcdctl /usr/bin

if [ ! -f /vagrant/kubernetes-v${KUBERNETES_VERSION}.tar.gz ]; then
    curl -sSL https://storage.googleapis.com/kubernetes-release/release/v${KUBERNETES_VERSION}/kubernetes.tar.gz -o /vagrant/kubernetes-v${KUBERNETES_VERSION}.tar.gz
fi
tar -xf /vagrant/kubernetes-v${KUBERNETES_VERSION}.tar.gz
tar -xf kubernetes/server/kubernetes-server-linux-amd64.tar.gz --strip-components=3 kubernetes/server/bin/kubectl kubernetes/server/bin/hyperkube
rm -rf kubernetes
mv hyperkube kubectl /usr/bin

sed -e "s%\${PORTAL_CIRD}%${PORTAL_CIRD}%" /vagrant/conf/kube-apiserver.service > /etc/systemd/system/kube-apiserver.service
sed -e "s%\${BRIDGE_IP}%${BRIDGE_IP}%" -e "s%\${CLUSTERDNS_IP}%${CLUSTERDNS_IP}%" -e "s%\${DNS_DOMAIN}%${DNS_DOMAIN}%" /vagrant/conf/kubelet.service > /etc/systemd/system/kubelet.service
cp /vagrant/conf/kube-controller-manager.service \
   /vagrant/conf/kube-scheduler.service \
   /vagrant/conf/kube-proxy.service \
   /vagrant/conf/kube-etcd.service \
  /etc/systemd/system/
systemctl enable kubelet kube-apiserver kube-controller-manager kube-scheduler kube-proxy kube-etcd
systemctl start kubelet kube-apiserver kube-controller-manager kube-scheduler kube-proxy kube-etcd

mkdir -p /etc/kubernetes/manifests
sed -e "s%\${BRIDGE_IP}%${BRIDGE_IP}%" /vagrant/conf/kube-master.yml > /etc/kubernetes/manifests/kube-master.yml
sed -e "s%\${DNS_DOMAIN}%${DNS_DOMAIN}%" -e "s%\${CLUSTERDNS_IP}%${CLUSTERDNS_IP}%" /vagrant/conf/kube-dns.yml > /etc/kubernetes/manifests/kube-dns.yml
cp /vagrant/conf/kube-dashboard.yml /etc/kubernetes/manifests/kube-dashboard.yml

# Install sysdig
echo "export SYSDIG_K8S_API=http://127.0.0.1:8080" >> /etc/profile.d/sysdig.sh

echo "Waiting for API server to show up"
until $(curl --output /dev/null --silent --head --fail http://localhost:8080); do
    printf '.'
    sleep 1
done

kubectl create -f /etc/kubernetes/manifests/kube-master.yml
kubectl create -f /etc/kubernetes/manifests/kube-dns.yml
kubectl create -f /etc/kubernetes/manifests/kube-dashboard.yml

# TODO wait for kube-dns to show up

# Clear tmp dir, because otherwise vagrant user would not have access
# See kubectl apply --schema-cache-dir=
rm -rf /tmp/kubectl.schema/

# Create bindfs related folders for fixing NFS mount permissions
mkdir /www-data
mkdir /nfs-data
# Add fstab line to auto-start bindfs relation when box starts
echo "bindfs#/nfs-data    /www-data    fuse    force-user=www-data,force-group=www-data    0    0" >> /etc/fstab

cat >> /etc/bash.bashrc << EOF
# enable bash completion in interactive shells
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
EOF

# Enable memory cgroups
sed -i -e 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="cgroup_enable=memory /' /etc/default/grub
update-grub

mkdir /sock/
chown vagrant /sock/
#echo 'ln $SSH_AUTH_SOCK /sock/sock' >> /home/vagrant/.bashrc

# cleanup
apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/*
