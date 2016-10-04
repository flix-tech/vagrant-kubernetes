.PHONY: default clean dist-clean add-box del-box

VERSION=1.4.0-r2

default: stripped.box box.meta

add-box: stripped.box
	vagrant box add vagrant-kubernetes stripped.box -f

del-box:
	vagrant box remove kubernetes

.vagrant/machines/default/virtualbox/id: vg-00-kubernetes.sh conf/*
	vagrant destroy -f
	SCRIPT=vg-00-kubernetes.sh vagrant up --provision
	vagrant halt

.vagrant/repartinioned: .vagrant/machines/default/virtualbox/id vg-*.sh
	$(eval MACHINEID:=$(shell cat .vagrant/machines/default/virtualbox/id))
	$(eval HDDFILE:=$(shell VBoxManage showvminfo --machinereadable $(MACHINEID) | grep "SATA Controller-0-0" | cut -d '=' -f 2))
	test -f cloned.vdi && vboxmanage closemedium disk cloned.vdi --delete || true
	VBoxManage clonehd $(HDDFILE) cloned.vdi --format vdi
	VBoxManage storageattach $(MACHINEID) --storagectl "SATA Controller" --port 0 --medium none
	VBoxManage closemedium disk $(HDDFILE) --delete
	VBoxManage modifyhd cloned.vdi --resize 122880 # 120 GB
	VBoxManage clonehd cloned.vdi $(HDDFILE) --format vmdk
	VBoxManage storageattach $(MACHINEID) --storagectl "SATA Controller" --port 0 --type hdd --medium $(HDDFILE)
	VBoxManage closemedium disk cloned.vdi --delete
	SCRIPT=vg-01-repartition.sh vagrant reload --provision
	SCRIPT=vg-02-reformat.sh vagrant reload --provision
	touch .vagrant/repartinioned

package.box: .vagrant/repartinioned Vagrantfile.dist
	rm -f package.box
	vagrant package --vagrantfile Vagrantfile.dist

tmp/Vagrantfile: package.box
	mkdir -p tmp
	tar xzf package.box -C tmp/
	sed -i.back '/vagrant_private_key/d' tmp/Vagrantfile
	rm -f tmp/Vagrantfile.back
	rm -f tmp/vagrant_private_key

stripped.box: tmp/Vagrantfile
	tar -czf stripped.box -C tmp/ .

box.meta: stripped.box box-metadata.sh
	./box-metadata.sh stripped.box ${VERSION} box.meta

clean: ; \
	vagrant destroy -f
	rm -f package.box
	rm -rf tmp
	rm -rf cloned.vdi
	rm -f stripped.box
	rm -f box.meta

dist-clean: clean
	rm -f etcd-*.tar.gz
	rm -f kubernetes-*.tar.gz