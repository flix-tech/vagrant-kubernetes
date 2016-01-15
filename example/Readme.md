# Kubernetes 1.1 Vagrant Machine

Please execute this command on your host to make sure you can reach the services inside the vagrant machine:

OSX:
```
sudo route -n add 10.0.0.0/24 10.10.0.2
```

Linux:
```
sudo ip route add 10.0.0.0/24 via 10.10.0.2
```

Windows:
```
route add 10.0.0.0 mask 255.255.255.0 10.10.0.2
```


## Try it out (inside the VM (`vagrant ssh`)):

List all endpoints
```
kubectl get endpoints
```

List all running services
```
kubectl get services
```

Get some insight
```
csysdig
```