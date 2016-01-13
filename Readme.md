# Kubernetes 1.1 Vagrant Machine

Please execute this command on your host to make sure you can reach the services inside the vagrant machine:

OSX:
```
sudo route -n add 10.0.0.0/24 10.10.0.3
```

Linux:
```
sudo ip route add 10.0.0.0/24 via 10.10.0.3
```

Windows:
```
route add 10.0.0.0 mask 255.255.255.0 10.10.0.3
```


On Arch Linux:
```
systemctl start nfs-server rpcbind
```

## Try it out (inside the VM (`vagrant ssh`)):

Start a pdf rendering service
```
kubectl run mfb-pdf --image=dcr.mfb.io/mfb-service-pdf
kubectl expose rc mfb-pdf --port=80
```

Create a dev environment
```
kubectl create -f /data/dev.rc.yml
kubectl create -f /data/dev.svc.yml
```

List all endpoints
```
kubectl get endpoints
```

List all running services
```
kubectl get services
```

Update a container
```
kubectl rolling-update mfb-dev mfb-dev-v2 --image=dcr.mfb.io/mfb-symfony-php7:latest
```

Get some insight
```
csysdig
```