#!/bin/sh
set -o verbose
set -o errexit

ETCD_VERSION=2.2.3
KUBERNETES_VERSION=1.1.4
DOCKER_VERSION=1.8.3

NET_CIRD=10.10.0.0/24
DOCKER_CIRD=10.10.0.128/25

BRIDGE_IP=10.10.0.2
BRIDGE_MASK=255.255.255.0

PORTAL_CIRD=10.0.0.1/24
CLUSTERDNS_IP=10.0.0.10
DOMAIN=example.local

# Disable all docker networking stuff, we will set it up manually
mkdir -p /etc/systemd/system/docker.service.d/
sed -e "s%\${DOCKER_CIRD}%${DOCKER_CIRD}%" /vagrant/conf/docker-override.conf > /etc/systemd/system/docker.service.d/override.conf

# Setup the bridge for docker, we connect it with the VirtualBox network (eth1)
sed -e "s%\${BRIDGE_IP}%${BRIDGE_IP}%" -e "s%\${BRIDGE_MASK}%${BRIDGE_MASK}%" /vagrant/conf/cbr0 > /etc/network/interfaces.d/cbr0

cp /vagrant/conf/vagrant-startup.service /etc/systemd/system/vagrant-startup.service

sed -e "s%\${NET_CIRD}%${NET_CIRD}%" /vagrant/conf/vagrant-startup.sh > /usr/bin/vagrant-startup
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
curl -s https://s3.amazonaws.com/download.draios.com/DRAIOS-GPG-KEY.public | apt-key add -

apt-get --quiet update
DEBIAN_FRONTEND=noninteractive apt-get --quiet --yes --force-yes upgrade
# Install bridge-utils first, so that we can get the bridget for docker up
apt-get -yq install bridge-utils ethtool htop \
    build-essential # for virtualbox guest plugin
ifup cbr0
apt-get --quiet --yes --force-yes install \
    bridge-utils ethtool htop build-essential docker-engine=${DOCKER_VERSION}-0~jessie \
    sysdig linux-headers-$(uname -r) # For sysdig

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

echo sed -e "s%\${PORTAL_CIRD}%${PORTAL_CIRD}%" /vagrant/conf/kube-api-server.service > /etc/systemd/system/kube-api-server.service
sed -e "s%\${PORTAL_CIRD}%${PORTAL_CIRD}%" /vagrant/conf/kube-api-server.service > /etc/systemd/system/kube-api-server.service
sed -e "s%\${BRIDGE_IP}%${BRIDGE_IP}%" -e "s%\${CLUSTERDNS_IP}%${CLUSTERDNS_IP}%" -e "s%\${DOMAIN}%${DOMAIN}%" /vagrant/conf/kubelet.service > /etc/systemd/system/kubelet.service
cp /vagrant/conf/kube-controller-manager.service \
   /vagrant/conf/kube-scheduler.service \
   /vagrant/conf/kube-proxy.service \
   /vagrant/conf/kube-etcd.service \
  /etc/systemd/system/
systemctl enable kubelet kube-api-server kube-controller-manager kube-scheduler kube-proxy kube-etcd
systemctl start kubelet kube-api-server kube-controller-manager kube-scheduler kube-proxy kube-etcd

mkdir -p /etc/kubernetes/manifests
sed -e "s%\${DOMAIN}%${DOMAIN}%" -e "s%\${CLUSTERDNS_IP}%${CLUSTERDNS_IP}%" /vagrant/conf/kube-dns.rc.yml > /etc/kubernetes/manifests/kube-dns.rc.yml
sed -e "s%\${DOMAIN}%${DOMAIN}%" -e "s%\${CLUSTERDNS_IP}%${CLUSTERDNS_IP}%" /vagrant/conf/kube-dns.svc.yml > /etc/kubernetes/manifests/kube-dns.svc.yml

# Install sysdig
echo "export SYSDIG_K8S_API=http://127.0.0.1:8080" >> /etc/profile.d/sysdig.sh

echo Waiting for API server to show up
until $(curl --output /dev/null --silent --head --fail http://localhost:8080); do
    printf '.'
    sleep 1
done

kubectl create -f /etc/kubernetes/manifests/kube-dns.rc.yml
kubectl create -f /etc/kubernetes/manifests/kube-dns.svc.yml

# Clear tmp dir, because otherwise vagrant user would not have access
# See kubectl apply --schema-cache-dir=
rm -rf /tmp/kubectl.schema/

apt-get clean && rm -rf /var/lib/apt/lists/*
